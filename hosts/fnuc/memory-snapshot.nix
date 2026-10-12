# Every 5 minutes, log which cgroups hold the most RAM + swap. systemd only
# reports a unit's memory peak when it stops, so after a memory incident
# there was no way to tell who held what at the moment it tipped over.
# Read back with: journalctl -t memory-snapshot
{ pkgs, ... }:
let
  memorySnapshot = pkgs.writeShellApplication {
    name = "memory-snapshot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
    ];
    text = builtins.readFile ./scripts/memory-snapshot.sh;
  };
in
{
  environment.systemPackages = [ memorySnapshot ];

  systemd.services.memory-snapshot = {
    description = "Log the biggest memory consumers";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${memorySnapshot}/bin/memory-snapshot";
      SyslogIdentifier = "memory-snapshot";
      # Must still run when user.slice is thrashing.
      Slice = "system.slice";
      MemoryMin = "16M";
      CPUWeight = 1000;
      IOWeight = 1000;
    };
  };

  systemd.timers.memory-snapshot = {
    description = "Log the biggest memory consumers every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      AccuracySec = "10s";
    };
  };
}
