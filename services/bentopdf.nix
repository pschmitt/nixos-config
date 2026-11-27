{ config, ... }:
let
  # renovate: datasource=docker depName=ghcr.io/alam00000/bentopdf depType=automerge
  bentopdfVersion = "2.8.12";
  bentopdfHost = "pdf.${config.domains.main}";
  bentopdfPort = 23686;
in
{
  virtualisation.oci-containers.containers.bentopdf = {
    image = "ghcr.io/alam00000/bentopdf:${bentopdfVersion}";
    autoStart = true;
    ports = [
      "127.0.0.1:${toString bentopdfPort}:8080"
    ];
  };

  services.containerServices.services.bentopdf = {
    port = bentopdfPort;
    hosts = [ bentopdfHost ];
    redirect = false;
    monitoring = {
      restart.systemdUnit = "${config.virtualisation.oci-containers.backend}-bentopdf.service";
      failCycles = 3;
      restartLimit = {
        restarts = 3;
        cycles = 15;
      };
    };
  };

}
