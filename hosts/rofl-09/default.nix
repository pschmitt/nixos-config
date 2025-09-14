{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./luks-data.nix

    ../../server
    ../../server/optimist.nix

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
    ../../services/postgresql.nix
    ../../services/rclone-bisync.nix
    ../../services/searxng.nix
    ../../services/turris-ssh-tunnel.nix
    (import ../../services/nfs/nfs-server.nix { inherit lib; })

    # misc
    ../../misc/rsync-fonts-to-rofl-13.nix

    # host-specific service config
    ./container-services.nix
    ./monit.nix
    ./restic.nix
  ];

  custom.cattle = false;
  custom.promptColor = "#088A39"; # nginx green

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
  # TODO remove once the migration is done
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOSMurkElc1C0mgQM97reY6D8bIg6cDX3TRx6mjd5Cru root@rofl-10"
  ];
}
