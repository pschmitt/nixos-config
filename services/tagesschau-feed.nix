# Podcast feed of the latest tagesschau editions (tagesschau.de), for Pocket Casts.
{ config, pkgs, ... }:
let
  domain = config.domains.main;
  host = "tagesschau.${domain}";
  port = 28847;
in
{
  systemd.services.tagesschau-feed = {
    description = "tagesschau podcast feed";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      PORT = toString port;
      TAGESSCHAU_BASE_URL = "https://${host}";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -I ${./tagesschau-feed/server.py}";
      DynamicUser = true;
      Restart = "always";
      RestartSec = 10;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    useACMEHost = "wildcard.${domain}";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
    };
  };

  services.monit.checks.tagesschau-feed = {
    type = "host";
    address = "127.0.0.1";
    group = "application";
    startProgram = "${config.systemd.package}/bin/systemctl start tagesschau-feed.service";
    stopProgram = "${config.systemd.package}/bin/systemctl stop tagesschau-feed.service";
    conditions = ''
      if failed port ${toString port} protocol http request "/" for 3 cycles then restart
      if 3 restarts within 5 cycles then alert
    '';
  };
}
