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
        useACMEHost = "wildcard.${domain}";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.atuin.port}";
          proxyWebsockets = true;
        };
      };
    };

    monit.checks = {
      atuin = {
        type = "host";
        address = "127.0.0.1";
        group = "application";
        startProgram = "${config.systemd.package}/bin/systemctl start atuin.service";
        stopProgram = "${config.systemd.package}/bin/systemctl stop atuin.service";
        conditions = ''
          if failed port ${toString config.services.atuin.port} protocol http request "/" for 3 cycles then restart
          if 3 restarts within 5 cycles then alert
        '';
      };
    };
  };
}
