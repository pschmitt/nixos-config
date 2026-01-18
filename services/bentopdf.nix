{ config, pkgs, ... }:
let
  bentopdfHost = "pdf.${config.domains.main}";
  bentopdfPort = 23686;
in
{
  virtualisation.oci-containers.containers.bentopdf = {
    image = "ghcr.io/alam00000/bentopdf:latest";
    autoStart = true;
    ports = [
      "127.0.0.1:${toString bentopdfPort}:8080"
    ];
  };

  services.nginx.virtualHosts."${bentopdfHost}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString bentopdfPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = ''
    check host "bentopdf" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-bentopdf.service"
        with timeout 180 seconds
      if failed
        port ${toString bentopdfPort}
        protocol http
        with timeout 90 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
