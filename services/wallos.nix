{ config, ... }:
let
  # renovate: datasource=docker depName=bellamy/wallos versioning=semver-coerced
  wallosVersion = "5.8.3";
  wallosHost = "subs.${config.domains.main}";
  wallosPort = 8282;
in
{
  virtualisation.oci-containers.containers.wallos = {
    image = "bellamy/wallos:${wallosVersion}";
    autoStart = true;
    ports = [
      "127.0.0.1:${toString wallosPort}:80"
    ];
    volumes = [
      "/srv/wallos/data/db:/var/www/html/db"
      "/srv/wallos/data/logos:/var/www/html/images/uploads/logos"
    ];
    environment = {
      TZ = config.time.timeZone;
    };
  };

  services.nginx.virtualHosts."${wallosHost}" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString wallosPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.checks = {
    wallos = {
      type = "host";
      address = "127.0.0.1";
      group = "container-services";
      restartUnit = "${config.virtualisation.oci-containers.backend}-wallos.service";
      conditions = ''
          with timeout 180 seconds
        if failed
          port ${toString wallosPort}
          protocol http
          with timeout 90 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
