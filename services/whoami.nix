{
  config,
  ...
}:
let
  # renovate: datasource=docker depName=traefik/whoami depType=automerge
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

  services.containerServices.services.whoami = {
    port = listenPort;
    hosts = [ hostName ];
    redirect = false;
    monitoring = {
      restart.systemdUnit = "${config.virtualisation.oci-containers.backend}-whoami.service";
      timeout = 15;
      failCycles = 3;
      restartLimit = {
        restarts = 3;
        cycles = 15;
      };
    };
  };

}
