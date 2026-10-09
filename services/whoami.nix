{
  config,
  ...
}:
let
  # renovate: datasource=docker depName=traefik/whoami
  whoamiVersion = "v1.12.0";
  listenPort = 19462;
  hostName = "whoami.${config.domains.main}";
in
{
  virtualisation.oci-containers.containers.whoami = {
    autoStart = true;
    image = "traefik/whoami:${whoamiVersion}";
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
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString listenPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.checks = {
    whoami = {
      type = "host";
      address = "127.0.0.1";
      group = "container-services";
      restartUnit = "${config.virtualisation.oci-containers.backend}-whoami.service";
      conditions = ''
        if failed
          port ${toString listenPort}
          protocol http
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
