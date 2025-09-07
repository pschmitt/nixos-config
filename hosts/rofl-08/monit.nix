{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:
let
  dcpPkg = inputs.docker-compose-bulk.packages.${pkgs.system}.docker-compose-bulk;

  mullvadExpiration = pkgs.writeShellScript "mullvad-expiration" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ]
    }
    ${builtins.readFile ./mullvad-expiration.sh}
  '';

  renderMonitConfig = pkgs.writeShellScript "render-monit-config" ''
    MONIT_CONF_DIR=/etc/monit/conf.d
    TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4)
    if [[ -z "$TAILSCALE_IP" ]]
    then
      echo "ERROR: Failed to determine Tailscale IP" >&2
    else
      cat > "$MONIT_CONF_DIR/gluetun" <<EOF
    check program "gluetun" with path "${pkgs.curl}/bin/curl -fsSL -x $TAILSCALE_IP:8888 https://myip.wtf/json"
      every 5 cycles
      group piracy
      depends on "docker compose services"
      restart program = "${pkgs.docker}/bin/docker compose -f /srv/piracy/docker-compose.yaml restart gluetun"
      if status != 0 then restart
      if 2 restarts within 10 cycles then alert
    EOF
    fi
  '';

  monitExtraConfig = ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert

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
  systemd.services.monit.preStart = lib.mkAfter "${renderMonitConfig}";
}
