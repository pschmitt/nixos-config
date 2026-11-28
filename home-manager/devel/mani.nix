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
      ExecStartPre = "-${pkgs.mani}/bin/mani --config %E/mani/${name}.yaml sync";
      ExecStart = "${pkgs.mani}/bin/mani --config %E/mani/${name}.yaml run update --all --silent";
    };

    Install = {
      WantedBy = [ ];
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

  # Removes the repositories below ~/devel that no mani config manages.
  maniPrune = pkgs.writeShellApplication {
    name = "mani-prune";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnused
      pkgs.yq-go
    ];
    text = builtins.readFile ./mani-prune.sh;
  };
in
{
  home.packages = [
    pkgs.mani
    maniPrune
  ];

  # Project lists and helper scripts (formerly in yadm); work.yaml is in the
  # private repo.
  xdg.configFile."mani" = {
    source = ./mani;
    recursive = true;
  };

  systemd.user.services = {
    mani = maniService "private";
    mani-work = maniService "work";
  };

  systemd.user.timers = {
    mani = maniTimer "private";
    mani-work = maniTimer "work";
  };
}
