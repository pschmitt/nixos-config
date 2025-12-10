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
      bentopdf = {
        port = 23686;
        hosts = [ (mkHost "pdf") ];
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
          restartAll = true;
        };
      };
      endurain = {
        port = 36387;
        hosts = [
          (mkHost "endurain")
          (mkHost "endurian") # common typo ;)
        ];
      };
      # hoarder = {
      #   port = 46273;
      #   hosts = [
      #     (mkHost "hoarder")
      #   ];
      # };
      linkding = {
        port = 54653;
        hosts = [
          (mkHost "ld")
          (mkHost "linkding")
        ];
      };
      mealie = {
        port = 63254;
        hosts = [ (mkHost "nom") ];
      };
      # memos = {
      #   port = 63667;
      #   hosts = [
      #     (mkHost "memos")
      #   ];
      # };
      n8n = {
        port = 5678;
        hosts = [ (mkHost "n8n") ];
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
      open-webui = {
        port = 6736;
        hosts = [ (mkHost "ai") ];
      };
      podsync = {
        port = 7637;
        hosts = [
          (mkHost "podcasts")
          (mkHost "podsync")
          (mkHostWithNode "podsync")
        ];
      };
      # traefik = {
      #   port = 8723; # http: 18723
      #   default = true;
      # };
      wallos = {
        port = 8282;
        hosts = [ (mkHost "subs") ];
      };
      whoami = {
        port = 19462;
        hosts = [ (mkHost "whoami") ];
        default = true;
      };
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
