{ lib, pkgs, ... }:
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
    ../../services/http.nix
    ../../services/stash.nix
    ../../services/tdarr-server.nix

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
}
