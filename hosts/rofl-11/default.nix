{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server

    (import ../../services/nfs/nfs-server.nix {
      inherit lib;
      exports = [
        "audiobooks"
        "books"
        "srv"
        "videos"
      ];
    })
    ../../profiles/arr.nix

    ../../services/audiobookshelf.nix
    # ../../services/calibre.nix  # superseded by shelfarr
    ../../services/http.nix
    ../../services/stash.nix
    ../../services/tor.nix

    ./container-services.nix
    ./monit.nix
    ./restic.nix
  ];

  hardware = {
    cattle = false;
    serverType = "openstack";
  };
  custom.promptColor = "#9C62C5"; # jellyfin purple

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  environment.systemPackages = with pkgs; [ yt-dlp ];
}
