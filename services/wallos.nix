{ config, pkgs, ... }:
let
  wallosHost = "subs.${config.domains.main}";
  wallosPort = 8282;
in
{
  virtualisation.oci-containers.containers.wallos = {
    image = "bellamy/wallos:latest";
    autoStart = true;
    ports = [
      "127.0.0.1:${toString wallosPort}:80"
    ];
    volumes = [
      "/srv/wallos/data/db:/var/www/html/db"
      "/srv/wallos/data/logos:/var/www/html/images/uploads/logos"
    ];
    environment = {
      TZ = "Europe/Berlin";
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

  services.monit.config = ''
    check host "wallos" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-wallos.service"
        with timeout 180 seconds
      if failed
        port ${toString wallosPort}
        protocol http
        with timeout 90 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
