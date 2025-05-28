{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./luks-data.nix

    ../../server
    ../../server/optimist.nix

    # backups
    # ./autorestic.nix
    # ./evernote.nix
    # ./rclone-bisync.nix
    # ./restic.nix
    #
    # ../../misc/docker-compose-netbird-ip-fix.nix
    #
    # # services
    # ../../services/bw-backup.nix
    # ../../services/changedetection-io.nix
    # ../../services/harmonia.nix
    # ../../services/http.nix
    # ../../services/luks-ssh-unlock-homelab.nix
    # (import ../../services/nfs/nfs-server.nix { inherit lib; })
    # # ../../services/mealie.nix
    # ./container-services.nix
    # ./forgejo.nix
    # ./http-static.nix
    # ./immich.nix
    # ./monit.nix
    # ./paperless-ngx.nix
    # ./podsync.nix
    # ./rsync-fonts-to-rofl-03.nix
    # ./turris-ssh-tunnel.nix
  ];

  custom.cattle = false;

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  # environment.systemPackages = with pkgs; [ ];
}
