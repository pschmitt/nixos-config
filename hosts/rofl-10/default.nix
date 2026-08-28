{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/network/roflnet.nix
    ../../profiles/network/ha-sshfs.nix

    # services
    # backups services
    ../../services/anika-blue.nix
    ../../services/atuin.nix
    ../../services/authelia.nix
    ../../services/backups/bitwarden.nix
    ../../services/bentopdf.nix
    ../../services/bichon.nix
    ../../services/changedetection-io-container.nix
    ../../services/clipcascade.nix
    ../../services/endurain.nix
    ../../services/filebrowser-quantum.nix
    ../../services/forgejo.nix
    ../../services/gitea-mirror.nix
    ../../services/github-backup.nix
    ../../services/harmonia.nix
    ../../services/hermes.nix
    ../../services/http-static.nix
    ../../services/http.nix
    ../../services/immich.nix
    ../../services/luks-ssh-unlock-homelab.nix
    ../../services/mealie.nix
    ../../services/matrix.nix
    ../../services/n8n.nix
    ../../services/netbox.nix
    ../../services/paperless-ngx.nix
    ../../services/authelia-nginx-bypass.nix
    ../../services/pinchflat.nix
    ../../services/podsync.nix
    ../../services/restic-remote.nix
    ../../services/poor-tools.nix
    ../../services/postgresql.nix
    ../../services/rclone-bisync.nix
    ../../services/searxng.nix
    ../../services/stricknani.nix
    ../../services/taskwarrior
    ../../services/turris-ssh-tunnel.nix
    ../../services/vaultwarden.nix
    ../../services/vdirsyncer.nix
    ../../services/wallos.nix
    ../../services/whoami.nix
    ../../services/wishlist.nix

    ../../services/nfs/nfs-server.nix
    ../../services/nfs/nfs-client.nix

    ./syncthing.nix

    # host-specific service config
    ./container-services.nix
    ./restic.nix

    ../../profiles/global/users/k8s-backdoor.nix
  ];

  hardware = {
    cattle = false;
    serverType = "openstack";
    biosBoot = lib.mkForce false;
  };
  # Dedicated key for the /mnt/ha sshfs mount (see profiles/network/ha-sshfs.nix):
  # rofl-10 is a server with no personal user key on disk, unlike workstations,
  # so it gets its own key authorized on the hass side instead.
  sops.secrets."hass/sshfs/private-key" = config.custom.mkSecret {
    mode = "0400";
  };
  custom = {
    promptColor = "#0B87CA"; # nextcloud blue
    homeAssistant.sshfs.identityFile = config.sops.secrets."hass/sshfs/private-key".path;
    homeAssistant.sshfs.host = "homeassistant.snake-eagle.ts.net";
  };

  nixHost.extraSubstituters = [
    "https://cache.rofl-13.brkn.lol"
    "https://cache.rofl-14.brkn.lol"
  ];

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  services = {
    nfsExports.enable = true;
    nfsMounts = {
      enable = true;
      server = "rofl-11.${config.domains.roflnet}";
      exports = [
        "audiobooks"
        "books"
        "videos"
      ];
    };
    nfsExports.allowedIps = [
      "100.64.0.0/10"
      "10.69.46.0/24"
    ];

    harmonia.extraVirtualHosts = [
      { domain = "cache.${config.domains.main}"; }
      { domain = "nix-cache.${config.domains.main}"; }
    ];
  };

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "rclone-bisync-reset-and-resync" ''
      set -euo pipefail

      lockfile="/var/cache/rclone/bisync/nextcloud_Documents..drive_Documents.lck"

      systemctl stop rclone-bisync-documents.service rclone-bisync-documents-resync.service
      rm -f "$lockfile"
      systemctl start rclone-bisync-documents-resync.service
    '')
  ];

}
