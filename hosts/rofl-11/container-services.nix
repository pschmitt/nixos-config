{ config, ... }:

let
  domain = config.custom.mainDomain;
  hostName = config.networking.hostName;
  mkHost = subdomain: "${subdomain}.${domain}";
  mkHostWithNode = subdomain: "${subdomain}.${hostName}.${domain}";

in
{
  imports = [
    ../../modules/container-services.nix
    ../../services/docker-compose-bulk.nix
  ];

  custom.containerServices = {
    enable = true;
    services = {
      ***REMOVED*** = {
        port = 29223;
        hosts = [ (mkHost "***REMOVED***") ];
        # credentialsFile = config.sops.secrets."htpasswd".path;
        # FIXME this leads to http 500 on the ***REMOVED*** service
        sso = true;
      };
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
      };
      lazylibrarian = {
        port = 5299;
        hosts = [ (mkHost "ll") ];
      };
      pp = {
        port = 7827;
        hosts = [ (mkHost "pp") ];
      };
      ***REMOVED*** = {
        port = 7878;
        hosts = [
          (mkHost "rdr")
          (mkHost "***REMOVED***")
          (mkHostWithNode "rdr")
          (mkHostWithNode "***REMOVED***")
        ];
        compose_yaml = "piracy";
      };
      ***REMOVED*** = {
        port = 8989;
        hosts = [
          (mkHost "snr")
          (mkHost "***REMOVED***")
          (mkHostWithNode "snr")
          (mkHostWithNode "***REMOVED***")
        ];
        compose_yaml = "piracy";
      };
      tdarr = {
        port = 8265;
        hosts = [
          (mkHost "tdarr")
          (mkHostWithNode "tdarr")
        ];
      };
      transmission = {
        port = 9091;
        hosts = [
          (mkHost "to")
          (mkHostWithNode "to")
        ];
        http_status_code = 401;
        compose_yaml = "piracy";
      };
    };
  };
}
