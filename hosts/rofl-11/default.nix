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
      # NFS is intentionally restricted to the authenticated VPN overlay;
      # the provider-controlled roflnet must not grant access to private data.
      "100.64.0.0/10"
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
