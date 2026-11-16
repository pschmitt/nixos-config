# Podcast feed and web player of the latest tagesschau editions (tagesschau.de),
# plus a time-shifted live stream of the edition on air.
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
      TAGESSCHAU_PLAYER_HTML = "${./tagesschau-feed/index.html}";
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
    locations = {
      # ARD's tagesschau podcast cover with an "ALLE" badge.
      "= /cover.jpg".alias = ./tagesschau-feed/cover.jpg;
      # The ARD "1" from the same cover, for the web player's header and favicon.
      "= /mark.jpg".alias = ./tagesschau-feed/mark.jpg;
      "/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        recommendedProxySettings = true;
      };
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
