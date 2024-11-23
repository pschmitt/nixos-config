{ config, ... }:

{
  virtualisation.oci-containers.containers.jcalapi = {
    image = "ghcr.io/pschmitt/jcalapi:latest";
    autoStart = true;
    environment = {
      TZ = "Europe/Berlin";
    };
    environmentFiles = [
      "${config.custom.homeDirectory}/.config/jcalapi/envrc.secret"
    ];
    volumes = [
      "${config.custom.homeDirectory}/.config/jcalapi:/config:Z"
    ];
    ports = [ "127.0.0.1:7042:7042" ];
    # extraOptions = [ "--network=host" ];
  };
}
