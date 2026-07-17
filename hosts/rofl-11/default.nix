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

    ../../services/nfs/nfs-server.nix
    ../../profiles/***REMOVED***.nix

    ../../services/audiobookshelf.nix
    # ../../services/calibre.nix  # superseded by ***REMOVED***
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

  services.nfsExports = {
    enable = true;
    exports = [
      "audiobooks"
      "books"
      "srv"
      "videos"
    ];
  };

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  environment.systemPackages = with pkgs; [ yt-dlp ];
}
