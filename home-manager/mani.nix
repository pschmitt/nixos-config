{ pkgs, ... }:

let
  # Helper to define a mani-update service
  maniService = name: {
    Unit = {
      Description = "mani update (${name})";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.mani}/bin/mani --config %E/mani/${name}.yaml run update --all";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Helper to define a timer for the service
  maniTimer = name: {
    Unit = {
      Description = "Timer for mani update (${name})";
      After = [ "network-online.target" ];
    };

    Timer = {
      OnBootSec = "1min"; # Run 1 minute after boot
      OnUnitActiveSec = "24h"; # Run once every 24 hours
      Persistent = true; # Ensures the timer remembers missed runs
    };

    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
in
{
  home.packages = [ pkgs.mani ];

  systemd.user.services = {
    mani = maniService "private";
    mani-work = maniService "work";
  };

  systemd.user.timers = {
    mani = maniTimer "private";
    mani-work = maniTimer "work";
  };
}
