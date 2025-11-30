{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs/nfs-server.nix {
      inherit lib;
      exports = [
        "srv"
        "videos"
      ];
    })
    (import ./../../services/nfs/nfs-client.nix {
      server = "rofl-10.nb.${config.custom.mainDomain}";
      exports = [ "books" ];
      mountPoint = "/mnt/data";
    })
    ../../services/http.nix
    ../../services/stash.nix
    ../../services/tdarr-server.nix
    ../../services/tor.nix
    ../../services/arr.nix

    ./container-services.nix
    ./monit.nix
    ./restic.nix
  ];

  custom.cattle = false;
  custom.promptColor = "#9C62C5"; # jellyfin purple

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  environment.systemPackages = with pkgs; [ yt-dlp ];

  systemd.services.piracy-restart = {
    description = "Recreate /srv/piracy docker compose stack";
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/srv/piracy";
    };
    path = [ pkgs.docker ];
    script = ''
      docker compose down
      docker compose up --force-recreate --remove-orphans -d
    '';
  };

  systemd.timers.piracy-restart = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "05:00";
      Persistent = true;
    };
  };
}
