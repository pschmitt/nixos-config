# Podcast feed, web player and time-shifted live stream of every tagesschau
# edition (github:pschmitt/tagesschau).
{ config, inputs, ... }:
let
  domain = config.domains.main;
  host = "tagesschau.${domain}";
  port = 28847;
in
{
  imports = [ inputs.tagesschau.nixosModules.default ];

  services = {
    tagesschau = {
      enable = true;
      inherit port;
      baseUrl = "https://${host}";
      # ARD's tagesschau podcast cover with an "ALLE" badge, and the ARD "1" from it.
      coverImage = ./tagesschau/cover.jpg;
      logoImage = ./tagesschau/logo.jpg;
    };

    nginx.virtualHosts.${host} = {
      forceSSL = true;
      useACMEHost = "wildcard.${domain}";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        recommendedProxySettings = true;
      };
    };

    monit.checks.tagesschau = {
      type = "host";
      address = "127.0.0.1";
      group = "application";
      startProgram = "${config.systemd.package}/bin/systemctl start tagesschau.service";
      stopProgram = "${config.systemd.package}/bin/systemctl stop tagesschau.service";
      conditions = ''
        if failed port ${toString port} protocol http request "/" for 3 cycles then restart
        if 3 restarts within 5 cycles then alert
      '';
    };
  };
}
