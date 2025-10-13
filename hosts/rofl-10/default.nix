{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../server
    ../../server/optimist.nix

    # services
    # backups services
    ../../services/anika-blue.nix
    ../../services/backups/autorestic.nix
    ../../services/backups/bitwarden.nix
    ../../services/backups/evernote.nix
    ../../services/calibre.nix
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
    ../../services/poor-tools.nix
    ../../services/postgresql.nix
    ../../services/rclone-bisync.nix
    ../../services/searxng.nix
    ../../services/turris-ssh-tunnel.nix
    (import ../../services/nfs/nfs-server.nix { inherit lib; })
    ../../services/nfs/nfs-client-rofl-11.nix

    # misc
    ../../misc/rsync-fonts-to-rofl-13.nix

    # host-specific service config
    ./container-services.nix
    ./monit.nix
    ./restic.nix
  ];

  custom.cattle = false;
  custom.promptColor = "#0B87CA"; # nextcloud blue

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];

}
