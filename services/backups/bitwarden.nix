{
  config,
  lib,
  pkgs,
  ...
}:

let
  bwLastBackup = pkgs.writeShellScript "bw-last-backup" ''
    THRESHOLD=''${1:-86400}
    NOW=$(${pkgs.coreutils}/bin/date '+%s')

    if [[ ! -s /srv/bw-backup/LAST_BACKUP ]]
    then
      echo "🚨 No backup timestamp found"
      exit 1
    fi

    LAST_BACKUP=$(${pkgs.coreutils}/bin/cat /srv/bw-backup/LAST_BACKUP)

    if [[ $((NOW - LAST_BACKUP)) -gt $THRESHOLD ]]
    then
      echo "🚨 Last backup was more than $THRESHOLD seconds ago"
      echo -e "📅 $(${pkgs.coreutils}/bin/date -d "@$LAST_BACKUP")"
      exit 1
    else
      echo -e "✅ Last backup was less than $THRESHOLD seconds ago"
      echo -e "📅 $(${pkgs.coreutils}/bin/date -d "@$LAST_BACKUP")"
      exit 0
    fi
  '';

  monitExtraConfig = ''
    check program "bw-backup" with path "${bwLastBackup}"
      group backup
      every 2 cycles
      if status > 0 then alert
  '';
in
{
  sops.secrets."bw-backup" = {
    inherit (config.custom) sopsFile;
  };

  virtualisation.oci-containers.containers = {
    bw-backup = {
      image = "ghcr.io/pschmitt/bw-backup:latest";
      pull = "always";
      autoStart = true;
      environmentFiles = [ config.sops.secrets."bw-backup".path ];
      environment = {
        CRON = "0 0 * * *";
        # DEBUG = "true";
        # START_RIGHT_NOW = "true";
      };
      volumes = [ "/srv/bw-backup:/data" ];
    };
  };

  services.monit.config = lib.mkAfter monitExtraConfig;
}
