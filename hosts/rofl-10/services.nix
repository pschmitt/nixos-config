{ config, ... }:
let
  wildcardCert = "wildcard.${config.domains.main}";
in
{
  imports = [
    ../../modules/container-services.nix
    ../../services/anika-blue.nix
    ../../services/archivebox.nix
    ../../services/atuin.nix
    ../../services/authelia-nginx-bypass.nix
    ../../services/authelia.nix
    ../../services/backups/bitwarden.nix
    ../../services/bichon.nix
    ../../services/bentopdf.nix
    ../../services/changedetection-io-container.nix
    ../../services/dawarich.nix
    ../../services/endurain.nix
    ../../services/filebrowser-quantum.nix
    ../../services/forgejo.nix
    ../../services/gitea-mirror.nix
    ../../services/github-backup.nix
    ../../services/glance.nix
    ../../services/harmonia.nix
    ../../services/hermes.nix
    ../../services/http-static.nix
    ../../services/http.nix
    ../../services/immich.nix
    ../../services/linkding.nix
    ../../services/luks-ssh-unlock/homelab.nix
    ../../services/matrix.nix
    ../../services/mealie.nix
    ../../services/monero-wallet-rpc-sync-receiver.nix
    ../../services/n8n.nix
    ../../services/netbox.nix
    ../../services/nextcloud.nix
    ../../services/paperless-ngx.nix
    ../../services/pinchflat.nix
    ../../services/podsync.nix
    ../../services/poor-tools.nix
    ../../services/postgresql.nix
    ../../services/rclone-bisync.nix
    ../../services/restic-remote.nix
    ../../services/rofl-10-container-networks.nix
    ../../services/searxng.nix
    ../../services/stricknani.nix
    ../../services/taskwarrior
    ../../services/trek.nix
    ../../services/turris-ssh-tunnel.nix
    ../../services/vaultwarden.nix
    ../../services/vdirsyncer.nix
    ../../services/wallos.nix
    ../../services/whoami.nix
    ../../services/wishlist.nix

    ./restic.nix
    ./syncthing.nix
  ];

  services.containerServices = {
    enable = true;
    defaultEnableACMEForDefaultHosts = false;
    defaultUseACMEHostForDefaultHosts = wildcardCert;
  };

  security.acme.certs."${wildcardCert}" = {
    domain = "*.${config.domains.main}";
    group = "nginx";
  };
}
