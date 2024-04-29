{ lib, config, pkgs, ... }:
let
  mullvadExpiration = pkgs.writeShellScript "mullvad-expiration" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq ]}
    ${builtins.readFile ./mullvad-expiration.sh}
  '';

  githubLastBackup = pkgs.writeShellScript "github-last-backup" ''
    THRESHOLD=''${1:-86400}
    NOW=$(${pkgs.coreutils}/bin/date '+%s')

    LAST_BACKUP=$(cat /srv/github-backup/data/LAST_UPDATED | \
      ${pkgs.findutils}/bin/xargs -I {} ${pkgs.coreutils}/bin/date -d '{}' '+%s')

    if [[ $((NOW - LAST_BACKUP)) -gt $THRESHOLD ]]
    then
      echo "🚨 Last backup was more than $THRESHOLD ago"
      exit 1
    else
      echo -e "✅ Last backup was less than $THRESHOLD ago"
      echo -e "📅 $(date -d "@$LAST_BACKUP")"
      exit 0
    fi
  '';

  renderMonitConfig = pkgs.writeShellScript "render-monit-config" ''
    MONIT_CONF_DIR=/etc/monit/conf.d
    TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4)
    if [[ -z "$TAILSCALE_IP" ]]
    then
      echo "ERROR: Failed to determine Tailscale IP" >&1
    else
      cat > "$MONIT_CONF_DIR/gluetun" <<EOF
    check program "gluetun" with path "${pkgs.curl}/bin/curl -fsSLv -x $TAILSCALE_IP:8888 http://www.gstatic.com/generate_204"
      group piracy
      depends on "docker compose services"
      restart program = "${pkgs.docker}/bin/docker compose -f /srv/piracy/docker-compose.yaml restart gluetun"
      if status != 0 then restart
      if status != 0 for 5 cycles then alert
    EOF
    fi
  '';

  generateHostCheck = params: ''
    check host ${params.svc} with address ${params.addr}
      group piracy
      depends on "docker compose services"
      restart program = "${pkgs.docker}/bin/docker compose -f /srv/${params.compose_yaml or params.svc}/docker-compose.yaml up -d --force-recreate ${params.svc}"
      if failed
        port 443
        protocol https
        ${if params.svc == "transmission" then "status 401" else ""}
      then restart
      if 5 restarts within 10 cycles then alert
  '';

  monitExtraConfig = ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert

    check program "docker compose services" with path "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk status"
      depends on "dockerd"
      group docker
      start program = "${pkgs.docker-compose-bulk}/bin/docker-compose-bulk up -d" with timeout 300 seconds
      every 2 cycles
      if status > 0 then start
      if 3 restarts within 10 cycles then unmonitor

    check program "github-backup" with path "${githubLastBackup}"
      group backup
      every 2 cycles
      if status > 0 then alert

    check program mullvad with path "${mullvadExpiration} --warning 15 ${config.age.secrets.mullvad-account.path}"
      group piracy
      every "11-13 3,6,12,18,23 * * *"
      if status != 0 then alert

    ${generateHostCheck { svc = "jellyfin"; addr = "media.heimat.dev"; }}
    ${generateHostCheck { svc = "nextcloud"; addr = "c.heimat.dev"; }};
    ${generateHostCheck { svc = "radarr"; addr = "radarr.heimat.dev"; compose_yaml = "piracy"; }}
    ${generateHostCheck { svc = "sonarr"; addr = "sonarr.heimat.dev"; compose_yaml = "piracy"; }}
    ${generateHostCheck { svc = "transmission"; addr = "to.heimat.dev"; compose_yaml = "piracy"; }}
  '';
in
{
  age.secrets.mullvad-account.file = ../../secrets/mullvad-account.age;

  services.monit.config = lib.mkAfter monitExtraConfig;
  systemd.services.monit.preStart = lib.mkAfter "${renderMonitConfig}";
}
