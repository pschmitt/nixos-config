{ config, pkgs, ... }:

let
  jcalapiPort = "7042";
in

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
    ports = [ "127.0.0.1:${jcalapiPort}:${jcalapiPort}" ];
    # extraOptions = [ "--network=host" ];
  };

  systemd.services."${config.virtualisation.oci-containers.backend}-jcalapi" = {
    preStart = ''
      ${pkgs.docker}/bin/docker pull ${config.virtualisation.oci-containers.containers.jcalapi.image}
    '';
    postStart = ''
      sleep 10
      ${pkgs.curl}/bin/curl -X POST http://localhost:${jcalapiPort}/reload
    '';
  };
}
