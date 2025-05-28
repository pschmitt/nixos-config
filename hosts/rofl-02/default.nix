{ pkgs, lib, ... }:
{
  imports = [
    # base, hardware config
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix
    ./luks-data.nix

    # services
    # backups services
    ../../services/backups/autorestic.nix
    ../../services/backups/bitwarden.nix
    ../../services/backups/evernote.nix
    ../../services/changedetection-io.nix
    ../../services/harmonia.nix
    ../../services/forgejo.nix
    ../../services/http.nix
    ../../services/http-static.nix
    ../../services/immich.nix
    ../../services/luks-ssh-unlock-homelab.nix
    # ../../services/mealie.nix # it's a container now!
    ../../services/paperless-ngx.nix
    ../../services/podsync.nix
    ../../services/rclone-bisync.nix
    ../../services/turris-ssh-tunnel.nix
    (import ../../services/nfs/nfs-server.nix { inherit lib; })

    # misc
    ../../misc/docker-compose-netbird-ip-fix.nix
    ../../misc/rsync-fonts-to-rofl-03.nix

    # host-specific services config
    ./container-services.nix
    ./monit.nix
    ./restic.nix
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
