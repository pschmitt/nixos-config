{ lib, pkgs, ... }:
let
  clockWatch = pkgs.writeShellApplication {
    name = "monit-clock-watch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.systemd
    ];
    text = builtins.readFile ./scripts/monit-clock-watch.sh;
  };
in
{
  systemd.services.monit-clock-watch = {
    description = "Reload monit after the system clock was stepped";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe clockWatch;
      RuntimeDirectory = "monit-clock-watch";
      RuntimeDirectoryPreserve = true;
    };
  };

  # Monotonic timer: unaffected by the very clock steps it is looking for.
  systemd.timers.monit-clock-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };
}
