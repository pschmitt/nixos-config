{
  lib,
  pkgs,
  ...
}:
let
  githubLastBackup = pkgs.writeShellScript "github-last-backup" ''
    THRESHOLD=''${1:-86400}
    NOW=$(${pkgs.coreutils}/bin/date '+%s')

    LAST_BACKUP=$(cat /srv/github-backup/data/LAST_UPDATED | \
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

  monitExtraConfig = ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert

    check program "docker compose services" with path "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk status"
      depends on "dockerd"
      group docker
      start program = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d" with timeout 600 seconds
      every 2 cycles
      if status > 0 then start
      if 3 restarts within 10 cycles then alert

    check program "github-backup" with path "${githubLastBackup}"
      group backup
      every 2 cycles
      if status > 0 then alert

    check host "ssh-tunnel-turris" with address 127.0.0.1
      group ssh
      if failed port 22887 protocol ssh for 2 cycles then alert
  '';
in
{
  services.monit.config = lib.mkAfter monitExtraConfig;
}
