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
    # ../../services/backups/autorestic.nix
    # ../../services/backups/bitwarden.nix
    # ../../services/backups/evernote.nix
    # ../../services/changedetection-io.nix
    ../../services/harmonia.nix
    # ../../services/forgejo.nix
    # ../../services/http.nix
    # ../../services/http-static.nix
    # ../../services/immich.nix
    # ../../services/luks-ssh-unlock-homelab.nix
    # ../../services/mealie.nix # it's a container now!
    # ../../services/paperless-ngx.nix
    # ../../services/podsync.nix
    # ../../services/rclone-bisync.nix
    # ../../services/turris-ssh-tunnel.nix
    # (import ../../services/nfs/nfs-server.nix { inherit lib; })

    # misc
    # ../../misc/rsync-fonts-to-rofl-03.nix

    # host-specific service config
    # ./container-services.nix
    # ./monit.nix
    # ./restic.nix
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

  custom.cattle = true;
  custom.promptColor = "#30353B";

  environment.systemPackages = with pkgs; [ yt-dlp ];
}
