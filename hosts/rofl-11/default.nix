{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/server

    (import ../../services/nfs/nfs-server.nix {
      inherit lib;
      exports = [
        "srv"
        "videos"
      ];
    })
    (import ./../../services/nfs/nfs-client.nix {
      server = "rofl-10.${config.domains.netbirdDomain}";
      exports = [ "books" ];
      mountPoint = "/mnt/data";
    })
    ../../services/http.nix
    ../../services/stash.nix
    ../../services/tdarr-server.nix
    ../../services/tor.nix
    ../../services/arr

    ./container-services.nix
    ./monit.nix
    ./restic.nix
  ];

  hardware.cattle = false;
  custom.promptColor = "#9C62C5"; # jellyfin purple

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  environment.systemPackages = with pkgs; [ yt-dlp ];
}
