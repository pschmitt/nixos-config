{
  config,
  lib,
  pkgs,
  ...
}:
let
  openWebuiHost = "ai.${config.domains.main}";
in
{
  sops = {
    secrets = {
      "open-webui/openai-api-key" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "open-webui.service" ];
      };
    };

    templates.openWebuiCredentials = {
      content = ''
        OPENAI_API_KEY=${config.sops.placeholder."open-webui/openai-api-key"}
      '';
    };
  };

  services = {
    open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = 28726;
      environmentFile = config.sops.templates.openWebuiCredentials.path;
    };

    nginx.virtualHosts."${openWebuiHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://${config.services.open-webui.host}:${toString config.services.open-webui.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "open-webui" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart open-webui"
        if failed
          port ${toString config.services.open-webui.port}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
