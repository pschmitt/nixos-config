{ config, ... }:

let
  domain = config.custom.mainDomain;
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
      ***REMOVED*** = {
        port = 29223;
        hosts = [ (mkHost "***REMOVED***") ];
        auth = {
          enable = true;
          # htpasswdFile = config.sops.secrets."htpasswd".path; # for type = "basic"
        };
        monitoring = {
          composeYaml = "piracy";
          restartAll = false;
          dependsOn = "gluetun";
          group = "piracy";
        };
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
      pp = {
        port = 7827;
        hosts = [ (mkHost "pp") ];
        monitoring = {
          composeYaml = "stash";
          group = "piracy";
        };
      };
      ***REMOVED*** = {
        port = 7878;
        hosts = [
          (mkHost "rdr")
          (mkHost "***REMOVED***")
          (mkHostWithNode "rdr")
          (mkHostWithNode "***REMOVED***")
        ];
        monitoring = {
          composeYaml = "piracy";
          restartAll = false;
          dependsOn = "gluetun";
          group = "piracy";
        };
      };
      ***REMOVED*** = {
        port = 8989;
        hosts = [
          (mkHost "snr")
          (mkHost "***REMOVED***")
          (mkHostWithNode "snr")
          (mkHostWithNode "***REMOVED***")
        ];
        monitoring = {
          composeYaml = "piracy";
          restartAll = false;
          dependsOn = "gluetun";
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
      transmission = {
        port = 9091;
        hosts = [
          (mkHost "to")
          (mkHostWithNode "to")
        ];
        monitoring = {
          composeYaml = "piracy";
          expectedHttpStatusCode = 401;
          restartAll = false;
          dependsOn = "gluetun";
          group = "piracy";
        };
      };
    };
  };
}
