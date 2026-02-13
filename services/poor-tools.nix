{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.poor-tools.nixosModules.default ];

  services = {
    poor-installer-web.enable = true;

    nginx.virtualHosts =
      let
        nginxConfig = {
          enableACME = true;
          # FIXME https://github.com/NixOS/nixpkgs/issues/210807
          acmeRoot = null;
          forceSSL = false; # disabled on purpose! tls is a luxury
          addSSL = true; # required to actually respond to https requests

          locations."/" = {
            proxyPass = "http://${toString config.services.poor-installer-web.bindHost}:${toString config.services.poor-installer-web.bindPort}";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
        };
      in
      {
        "poor.tools" = nginxConfig;
        "poor.${config.domains.main}" = nginxConfig;
      };

    monit.config = lib.mkAfter ''
      check host "poor-installer-web" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart poor-installer-web.service"
        if failed
          port ${toString config.services.poor-installer-web.bindPort}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
