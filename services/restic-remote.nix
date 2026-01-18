{ config, lib, ... }:
{
  imports = [ ../modules/restic-remote.nix ];

  services.restic-remote = {
    enable = true;
    instances.turris = {
      user = "root";
      host = "turris.${config.domains.vpn}";
      identityFile = config.sops.secrets."restic-remote/turris/sshkey".path;
      environmentFile = config.sops.secrets."restic-remote/turris/env".path;
      repositoryFile = null; # RESTIC_REPOSITORY will be read from environmentFile
      # Paths on the remote system to exclude from backup
      exclude = [
        "/boot"
        "/dev"
        "/mnt"
        "/overlay"
        "/proc"
        "/rom"
        "/run"
        "/sys"
        "/srv/docker"
        "/syslog"
        "/tmp"
        "/var"
      ];
      pruneOpts = [
        "--keep-last 5"
        "--keep-daily 1"
        "--keep-weekly 2"
        "--keep-monthly 3"
        "--keep-yearly 10"
        "--keep-within 14d"
      ];
    };
  };

  # Exclude remote mount directory from main restic backup to avoid backing up remote filesystems
  services.restic.backups.main.exclude = lib.mkAfter [
    "/var/lib/restic-remote/mounts"
  ];

}
