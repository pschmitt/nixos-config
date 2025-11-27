{
  lib,
  config,
  pkgs,
  ...
}:
let
  mullvadExpiration = pkgs.writeShellScript "mullvad-expiration" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ]
    }
    ${builtins.readFile ../../common/monit/mullvad-expiration.sh}
  '';

  monitExtraConfig = ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert

    check program "gluetun" with path "${pkgs.docker}/bin/docker exec gluetun /usr/bin/wget -qO- --tries=1 --timeout=5 http://127.0.0.1:9999/health"
      group piracy
      depends on dockerd
      restart program = "${pkgs.docker}/bin/docker compose -f /srv/piracy/docker-compose.yaml restart gluetun"
      if status != 0 for 3 cycles then restart
      if 2 restarts within 10 cycles then alert

    check program "gluetun-http-proxy" with path "${pkgs.curl}/bin/curl -fsSL -x 127.0.0.1:8888 https://myip.wtf/json"
      group piracy
      depends on gluetun
      every 5 cycles
      if status != 0 then alert

    check host "gluetun-socks5-proxy" with address 127.0.0.1
      group piracy
      depends on gluetun
      if failed port 1080 protocol default then alert

    check program mullvad with path "${mullvadExpiration} --warning 15 ${
      config.sops.secrets."mullvad/account".path
    }"
      group piracy
      every "11-13 3,6,12,18,23 * * *"
      if status != 0 then alert
  '';
in
{
  sops.secrets."mullvad/account".sopsFile = config.custom.sopsFile;

  services.monit.config = lib.mkAfter monitExtraConfig;
}
