{ pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix
    ./luks-data.nix

    # backups
    ./autorestic.nix
    ./evernote.nix
    ./rclone-bisync.nix
    ./restic.nix

    ../../misc/docker-compose-netbird-ip-fix.nix

    # services
    ../../services/bw-backup.nix
    ../../services/changedetection-io.nix
    ../../services/harmonia.nix
    ../../services/http.nix
    ../../services/luks-ssh-unlock-homelab.nix
    ../../services/nfs-server.nix
    # ../../services/mealie.nix
    ./container-services.nix
    ./forgejo.nix
    ./http-static.nix
    ./immich.nix
    ./monit.nix
    ./paperless-ngx.nix
    ./podsync.nix
    ./rsync-fonts-to-rofl-03.nix
    ./turris-ssh-tunnel.nix
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
