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
      jellyfin = {
        port = 8096;
        hosts = [
          (mkHost "tv")
          (mkHostWithNode "jelly")
          (mkHost "jelly")
          (mkHostWithNode "jellyfin")
          (mkHost "jellyfin")
          (mkHost "media")
        ];
        monitoring = {
          composeYaml = "jellyfin";
          group = "jellyfin";
        };
      };
      seerr = {
        port = 5055;
        hosts = [
          (mkHost "jellyseerr")
          (mkHost "jellyseerr.arr")
          (mkHost "seerr")
          (mkHost "seerr.arr")
        ];
        monitoring = {
          composeYaml = "jellyfin";
          group = "jellyfin";
        };

        auth.type = "sso";
      };
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
