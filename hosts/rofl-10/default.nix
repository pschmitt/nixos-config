{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../common/server

    # services
    # backups services
    ../../services/anika-blue.nix
    ../../services/atuin.nix
    ../../services/stricknani.nix
    ../../services/authelia.nix
    ../../services/audiobookshelf.nix
    ../../services/backups/autorestic.nix
    ../../services/backups/bitwarden.nix
    ../../services/backups/evernote.nix
    ../../services/calibre.nix
    ../../services/changedetection-io-container.nix
    ../../services/clipcascade.nix
    ../../services/harmonia.nix
    ../../services/forgejo.nix
    ../../services/http.nix
    ../../services/http-static.nix
    ../../services/immich.nix
    ../../services/luks-ssh-unlock-homelab.nix
    # ../../services/mealie.nix # it's a container now!
    ../../services/n8n.nix
    ../../services/open-webui.nix
    ../../services/paperless-ngx.nix
    ../../services/pinchflat.nix
    ../../services/podsync.nix
    ../../services/poor-tools.nix
    ../../services/postgresql.nix
    ../../services/rclone-bisync.nix
    ../../services/searxng.nix
    ../../services/turris-ssh-tunnel.nix
    ../../services/vaultwarden.nix
    ../../services/vdirsyncer.nix
    ../../services/wishlist.nix
    (import ../../services/nfs/nfs-server.nix { inherit lib; })
    ../../services/nfs/nfs-client-rofl-11.nix

    # host-specific service config
    ./container-services.nix
    ./monit.nix
    ./restic.nix

    ../../common/global/users/k8s-backdoor.nix
  ];

  hardware = {
    cattle = false;
    serverType = "openstack";
  };
  custom.promptColor = "#0B87CA"; # nextcloud blue

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];

}
