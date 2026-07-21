{ config, ... }:

let
  domain = config.domains.main;
  inherit (config.networking) hostName;
  mkHost = subdomain: "${subdomain}.${domain}";
  mkHostWithNode = subdomain: "${subdomain}.${hostName}.${domain}";

in
{
  imports = [
    ../../modules/container-services.nix
  ];

  custom.containerServices = {
    enable = true;
    services = {
      tdarr = {
        port = 8265;
        hosts = [
          (mkHost "tdarr")
          (mkHostWithNode "tdarr")
        ];
        monitoring.restart.systemdUnit = config.virtualisation.oci-containers.containers.tdarr.serviceName;
      };
    };
  };
}
