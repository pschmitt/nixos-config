{ config, pkgs, ... }:
let
  xdgConfigHome = "${config.home.homeDirectory}/.config";
  xdgDataHome = "${config.home.homeDirectory}/.local/share";

  timewsyncWrapper = pkgs.writeShellApplication {
    name = "timewsync-wrapper";
    runtimeInputs = [
      pkgs.jq
      pkgs.timew-sync-client
      pkgs.timewarrior
    ];
    text = builtins.readFile ./scripts/timewsync-wrapper.sh;
  };
in
{
  home.packages = with pkgs; [
    taskwarrior3
    timew-sync-client
    timewarrior
    timewarrior-jirapush
    python312Packages.bugwarrior
  ];

  # Same values as the interactive shell's xdg.zsh (see also the noctalia
  # plugin's own TIMEWARRIORDB override, profiles/laptop/noctalia.nix) —
  # systemd user services do not inherit the interactive shell's exports.
  systemd.user.services.taskwarrior-sync = {
    Unit.Description = "Sync taskwarrior and timewarrior";
    Service = {
      Type = "oneshot";
      Environment = [
        "XDG_CONFIG_HOME=${xdgConfigHome}"
        "XDG_DATA_HOME=${xdgDataHome}"
        "TIMEWARRIORDB=${xdgConfigHome}/timewarrior"
        "TASKRC=${xdgConfigHome}/taskwarrior/taskrc"
        "TASKDATA=${xdgDataHome}/taskwarrior"
      ];
      ExecStart = [
        "${timewsyncWrapper}/bin/timewsync-wrapper"
        "${pkgs.taskwarrior3}/bin/task sync"
        "${pkgs.taskwarrior3}/bin/task sync"
      ];
    };
  };

  systemd.user.timers.taskwarrior-sync = {
    Unit.Description = "Sync taskwarrior and timewarrior periodically";
    Timer = {
      OnUnitInactiveSec = "30m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
