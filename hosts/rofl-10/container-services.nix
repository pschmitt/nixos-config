{ config, ... }:

let
  domain = config.domains.main;
  inherit (config.networking) hostName;
  mkHost = subdomain: "${subdomain}.${domain}";
  mkHostWithNode = subdomain: "${subdomain}.${hostName}.${domain}";
  wildcardCert = "wildcard.${domain}";
in
{
  imports = [
    ../../modules/container-services.nix
  ];

  custom.containerServices = {
    enable = true;
    defaultEnableACMEForDefaultHosts = false;
    defaultUseACMEHostForDefaultHosts = wildcardCert;
    services = {
      alby-hub = {
        port = 25294;
        hosts = [ (mkHost "alby") ];
      };
      archivebox = {
        port = 27244;
        hosts = [
          (mkHost "arc")
          (mkHost "archive")
          (mkHost "archivebox")
          (mkHostWithNode "arc")
          (mkHostWithNode "archive")
          (mkHostWithNode "archivebox")
        ];
      };
      bichon = {
        port = 15630;
        hosts = [ (mkHost "bichon") ];
      };
      changedetection = {
        port = 24264;
        hosts = [ (mkHost "changes") ];
      };
      dawarich = {
        port = 32927;
        hosts = [
          (mkHost "dawarich")
          (mkHost "location")
        ];
        monitoring = {
          path = "/api/v1/health";
          restartAll = true;
        };
      };
      linkding = {
        port = 54653;
        hosts = [
          (mkHost "ld")
          (mkHost "linkding")
        ];
      };
      nextcloud = {
        port = 63982;
        tls = true;
        hosts = [
          (mkHost "c")
          (mkHost "nextcloud")
          (mkHostWithNode "c")
          (mkHostWithNode "nextcloud")
        ];
      };
      # traefik = {
      #   port = 8723; # http: 18723
      #   default = true;
      # };
      wikijs = {
        port = 9454;
        hosts = [ (mkHost "wiki") ];
      };
    };
  };

  # wildcard cert
  security.acme.certs."${wildcardCert}" = {
    domain = "*.${domain}";
    group = "nginx";
  };
}
