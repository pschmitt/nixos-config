{ pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    ./luks-data.nix
    ./rclone-bisync.nix
    ./restic.nix

    ./rsync-fonts-to-rofl-03.nix
    ./docker-compose-netbird-ip-fix.nix
    ../../server/luks-ssh-unlock-homelab.nix

    # services
    ../../misc/harmonia.nix
    ../../misc/http.nix
    ./archivebox.nix
    # ./email.nix
    ./immich.nix
    ./jellyfin.nix
    ./monit.nix
    ./nfs-server.nix
    ./paperless-ngx.nix
    ./piracy.nix
    ./podsync.nix
  ];

  # Enable networking
  networking = {
    hostName = "rofl-02";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  custom.promptColor = "208"; # orange

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
