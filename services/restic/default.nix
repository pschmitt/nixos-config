{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf (!config.hardware.cattle) {
    sops.secrets = {
      "restic/env" = {
        inherit (config.custom) sopsFile;
      };
      "restic/password" = {
        inherit (config.custom) sopsFile;
      };
      "restic/repository" = {
        inherit (config.custom) sopsFile;
      };
    };

    environment.systemPackages = [ pkgs.restic ];

    services.restic.backups.main = {
      environmentFile = config.sops.secrets."restic/env".path;
      passwordFile = config.sops.secrets."restic/password".path;
      repositoryFile = config.sops.secrets."restic/repository".path;

      paths = [ "/etc/nixos" ];

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
        "--keep-tag keep"
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
        # Check if the repo is locked
        # https://forum.restic.net/t/detecting-stale-locks/1889/8
        if ! ${pkgs.restic}/bin/restic list keys
        then
          echo "List keys failed, repo is probably locked." >&2
          ${pkgs.curl}/bin/curl -m 10 --retry 5 -X POST \
            -H "Content-Type: text/plain" \
            --data "Backup failed: repo locked? (nix restic-main)" \
            "$HEALTHCHECK_URL/fail"
          exit 1
        fi

        # Check if there was a backup today
        TODAY=$(${pkgs.coreutils}/bin/date -I)
        if ! ${pkgs.restic}/bin/restic snapshots --json | \
           ${pkgs.jq}/bin/jq -er --arg today "$TODAY" '
            .[] | select(.time | startswith($today))
          ' >/dev/null
        then
          ${pkgs.curl}/bin/curl -m 10 --retry 5 -X POST \
            -H "Content-Type: text/plain" \
            --data "Backup failed: no backup on $TODAY (nix restic-main)" \
            "$HEALTHCHECK_URL/fail"
          exit 1
        fi

        # Backup successful
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
