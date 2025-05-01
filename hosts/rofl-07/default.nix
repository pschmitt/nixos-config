{ pkgs, lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./luks-data.nix

    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs/nfs-client.nix { mountPoint = "/mnt/rofl-02"; })
    (import ../../services/nfs/nfs-server.nix {
      inherit lib;
      exports = [
        "srv"
        "videos"
      ];
    })
    ../../misc/docker-compose-netbird-ip-fix.nix
    ../../services/http.nix
    ../../services/tdarr-server.nix
    ./container-services.nix
    ./restic.nix
  ];

  custom.cattle = false;

  # Enable networking
  networking = {
    hostName = "rofl-07";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  systemd.services.docker-compose-bulk-up = {
    after = [
      "network.target"
      "docker.service"
      "mnt-data.mount"
    ];
    requires = [
      "docker.service"
      "mnt-data.mount"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d";
    };
  };

  environment.systemPackages = with pkgs; [ yt-dlp ];
}
