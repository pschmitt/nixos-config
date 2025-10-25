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
      cwabd = {
        port = 29223;
        hosts = [ (mkHost "cwabd") ];
        # credentialsFile = config.sops.secrets."htpasswd".path;
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
      radarr = {
        port = 7878;
        hosts = [
          (mkHost "rdr")
          (mkHost "radarr")
          (mkHostWithNode "rdr")
          (mkHostWithNode "radarr")
        ];
        compose_yaml = "piracy";
      };
      sonarr = {
        port = 8989;
        hosts = [
          (mkHost "snr")
          (mkHost "sonarr")
          (mkHostWithNode "snr")
          (mkHostWithNode "sonarr")
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
