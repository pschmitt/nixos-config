{ config, ... }:
let
  domain = config.domains.main;
in
{
  services = {
    atuin = {
      enable = true;
      openRegistration = false;
      host = "127.0.0.1";
      port = 28846;
      maxHistoryLength = 100000;
    };

    nginx.virtualHosts = {
      "atuin.${domain}" = {
        forceSSL = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        useACMEHost = "wildcard.${domain}";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.atuin.port}";
          proxyWebsockets = true;
        };
      };
    };

    monit.config = ''
      check host "atuin" with address 127.0.0.1
        group application
        start program = "${config.systemd.package}/bin/systemctl start atuin.service"
        stop program = "${config.systemd.package}/bin/systemctl stop atuin.service"
        if failed port ${toString config.services.atuin.port} protocol http request "/" then restart
        if 3 restarts within 5 cycles then alert
    '';
  };
}
