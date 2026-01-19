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
      pp = {
        port = 7827;
        hosts = [ (mkHost "pp") ];
        monitoring = {
          composeYaml = "stash";
          group = "piracy";
        };
      };
      tdarr = {
        port = 8265;
        hosts = [
          (mkHost "tdarr")
          (mkHostWithNode "tdarr")
        ];
      };
    };
  };
}
