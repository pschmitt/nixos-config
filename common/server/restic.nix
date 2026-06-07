{
  config,
  lib,
  pkgs,
  ...
}:
let
  resticLastBackup = pkgs.writeShellScript "restic-last-backup" ''
    THRESHOLD=''${1:-86400}
    NOW=$(${pkgs.coreutils}/bin/date '+%s')

    LAST_BACKUP=$(/run/current-system/sw/bin/restic-main snapshots --json | \
      ${pkgs.jq}/bin/jq -r '.[-1].time' | \
      ${pkgs.findutils}/bin/xargs -I {} ${pkgs.coreutils}/bin/date -d '{}' '+%s')

    if [[ $((NOW - LAST_BACKUP)) -gt $THRESHOLD ]]
    then
      echo "🚨 Last backup was more than $THRESHOLD ago"
      echo -e "📅 $(date -d "@$LAST_BACKUP")"
      exit 1
    else
      echo -e "✅ Last backup was less than $THRESHOLD ago"
      echo -e "📅 $(date -d "@$LAST_BACKUP")"
      exit 0
    fi
  '';
in
{
  imports = [ ../../services/restic ];

  config = lib.mkIf (!config.hardware.cattle) {
    services.restic.backups.main = {
      paths = [
        "/etc"
        "/var/lib"
        "${config.mainUser.homeDirectory}"
      ];
      exclude = [
        "/var/lib/docker"
        "/var/lib/cni"
        "/var/lib/containers"
        "/var/lib/flatpak"
        "/var/lib/systemd"
        "/var/lib/udisks"
      ];
    };

    # The monit check lives here (not in monit.nix) so that hosts without
    # restic backups do not get a permanently failing check.
    services.monit.config = ''
      check program "restic backup status" with path "${resticLastBackup}"
        group storage
        every 5 cycles
        if status > 0 then alert
    '';
  };
}
