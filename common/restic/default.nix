{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (!config.custom.cattle) {
    sops.secrets = {
      "restic/env" = {
        sopsFile = config.custom.sopsFile;
      };
      "restic/password" = {
        sopsFile = config.custom.sopsFile;
      };
      "restic/repository" = {
        sopsFile = config.custom.sopsFile;
      };
    };

    environment.systemPackages = [ pkgs.restic ];

    services.restic.backups.main = {
      environmentFile = config.sops.secrets."restic/env".path;
      passwordFile = config.sops.secrets."restic/password".path;
      repositoryFile = config.sops.secrets."restic/repository".path;

      paths = lib.mkDefault [
        "/etc/nixos"
        "${config.custom.homeDirectory}/devel"
        "${config.custom.homeDirectory}/Documents"
        "${config.custom.homeDirectory}/Pictures"
        "${config.custom.homeDirectory}/.config/obs-studio"
        "${config.custom.homeDirectory}/.var/app/com.obsproject.Studio/config/obs-studio"
      ];
      timerConfig = {
        OnCalendar = "12:30:00";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-last 5"
        "--keep-within 14d"
        "--keep-daily 1"
        "--keep-weekly 1"
        "--keep-monthly 1"
        "--keep-yearly 10"
        "--keep-tag do-not-delete"
        "--keep-tag keep-forever"
        "--keep-tag forever"
      ];
      initialize = true;
      createWrapper = true;
      exclude = [ ];
      backupPrepareCommand = ''
        ${pkgs.curl}/bin/curl -m 10 --retry 5 -X POST \
          -H "Content-Type: text/plain" \
          --data "Starting backup (nix restic-main)" \
          "$HEALTHCHECK_URL/start"
      '';
      backupCleanupCommand = ''
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/restic
        ${pkgs.coreutils}/bin/date +%s > /var/lib/restic/last-backup

        ${pkgs.curl}/bin/curl -m 10 --retry 5 -X POST \
          -H "Content-Type: text/plain" \
          --data "Backup successful (nix restic-main)" \
          "$HEALTHCHECK_URL"
      '';
    };
  };
}
