{
  config,
  lib,
  pkgs,
  ...
}:
let
  xdgConfigHome = config.xdg.configHome;
  xdgDataHome = config.xdg.dataHome;

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
    python3Packages.bugwarrior
  ];

  # Config files (formerly in yadm). The taskd sync settings stay an
  # unmanaged local file (~/.config/taskwarrior/taskd, included by taskrc);
  # bugwarriorrc and timewsync.conf are in the private repo.
  xdg.configFile = {
    "taskwarrior" = {
      source = ./taskwarrior;
      recursive = true;
    };
    "bugwarrior/udas".source = ./bugwarrior-udas;
    "timewarrior/data".source = config.lib.file.mkOutOfStoreSymlink "${xdgDataHome}/timewarrior";
    "timewarrior/extensions/jirapush".source = lib.getExe pkgs.timewarrior-jirapush;
  };
  # taskrc's data.location is ~/.local/share/taskwarrior; hooks live there
  xdg.dataFile."taskwarrior/hooks".source =
    config.lib.file.mkOutOfStoreSymlink "${xdgConfigHome}/taskwarrior/hooks";

  # Same values as the interactive shell's xdg.zsh (see also the noctalia
  # plugin's own TIMEWARRIORDB override, home-manager/gui/noctalia-shell.nix) —
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
      OnUnitInactiveSec = "6h";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
