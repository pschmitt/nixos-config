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
    ../../profiles/network/roflnet.nix

    ../../services/nfs/nfs-server.nix

    ../../services/audiobookshelf.nix
    ../../services/authelia-nginx-bypass.nix
    # ../../services/calibre.nix  # superseded by a service in the private repo
    ../../services/http.nix
    ../../services/jellyfin.nix
    ../../services/seerr.nix
    ../../services/tdarr-server.nix
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
    allowedIps = [
      "100.64.0.0/10"
      "10.69.46.0/24"
    ];
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
