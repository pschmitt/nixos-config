{
  config,
  lib,
  pkgs,
  ...
}:
let
  listenPort = 19462;
  hostName = "whoami.${config.domains.main}";
in
{
  virtualisation.oci-containers.containers.whoami = {
    autoStart = true;
    image = "traefik/whoami";
    pull = "always";
    cmd = [ "--verbose" ];
    ports = [
      "127.0.0.1:${toString listenPort}:80"
    ];
    environment = {
      HOSTNAME = config.networking.hostName;
    };
  };

  services.nginx.virtualHosts."${hostName}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString listenPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "whoami" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-whoami.service"
      if failed
        port ${toString listenPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
