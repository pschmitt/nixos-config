{ lib, pkgs, ... }:
let
  evernoteLastBackup = pkgs.writeShellScript "evernote-last-backup" ''
    set -euo pipefail

    THRESHOLD=''${1:-129600} # 36h by default
    BACKUP_DIR="/srv/evernote-backup/data/backups"
    LATEST_LINK="$BACKUP_DIR/latest"

    if [[ ! -L "$LATEST_LINK" ]]
    then
      echo "🚨 latest symlink missing in $BACKUP_DIR"
      exit 1
    fi

    TARGET=$(readlink -f "$LATEST_LINK")
    if [[ -z "$TARGET" || ! -d "$TARGET" ]]
    then
      echo "🚨 latest does not point to a directory: ''${TARGET:-<empty>}"
      exit 1
    fi

    MTIME=$(stat -c %Y "$TARGET")
    NOW=$(date +%s)

    if [[ $((NOW - MTIME)) -gt $THRESHOLD ]]
    then
      echo "🚨 Last backup is stale"
      echo -e "📅 $(date -d "@$MTIME")"
      exit 1
    else
      echo "✅ Last backup is fresh enough"
      echo -e "📅 $(date -d "@$MTIME")"
      exit 0
    fi
  '';

  monitExtraConfig = ''
    check program "evernote-backup" with path "${evernoteLastBackup}"
      group backup
      every 2 cycles
      if status > 0 then alert
  '';
in
{
  systemd = {
    services.evernote-backup = {
      description = "Evernote Backup Service";
      path = with pkgs; [
        bash
        coreutils
        docker
      ];
      script = ''
        /srv/evernote-backup/bin/evernote-backup-all.sh
      '';
    };

    timers.evernote-backup = {
      description = "Daily Evernote Backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "7200"; # 2h
        Persistent = true;
      };
    };
  };

  services.monit.config = lib.mkAfter monitExtraConfig;
}
