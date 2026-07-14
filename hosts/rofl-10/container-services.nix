{ config, pkgs, ... }:

let
  domain = config.domains.main;
  inherit (config.networking) hostName;
  mkHost = subdomain: "${subdomain}.${domain}";
  mkHostWithNode = subdomain: "${subdomain}.${hostName}.${domain}";
  wildcardCert = "wildcard.${domain}";
  nextcloudHealthCheck = pkgs.writeShellScript "nextcloud-health-check" ''
    exec ${pkgs.curl}/bin/curl \
      --silent \
      --show-error \
      --fail \
      --insecure \
      --max-time 20 \
      --noproxy '*' \
      --resolve nextcloud.${domain}:63982:127.0.0.1 \
      "https://nextcloud.${domain}:63982/status.php" \
      >/dev/null
  '';
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
        monitoring.restart.composePath = "alby-hub";
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
        monitoring.restart.composePath = "archivebox";
      };
      bichon = {
        port = 15630;
        hosts = [ (mkHost "bichon") ];
        monitoring.restart.systemdUnit = config.virtualisation.oci-containers.containers.bichon.serviceName;
      };
      changedetection = {
        port = 24264;
        hosts = [ (mkHost "changes") ];
        monitoring.restart.systemdUnit =
          config.virtualisation.oci-containers.containers.changedetection-io.serviceName;
      };
      dawarich = {
        port = 32927;
        hosts = [
          (mkHost "dawarich")
          (mkHost "location")
        ];
        monitoring = {
          path = "/api/v1/health";
          restart.composePath = "dawarich";
        };
      };
      linkding = {
        port = 54653;
        hosts = [
          (mkHost "ld")
          (mkHost "linkding")
        ];
        monitoring.restart.composePath = "linkding";
      };
      nextcloud = {
        port = 63982;
        tls = true;
        monitoring = {
          program = "${nextcloudHealthCheck}";
          restart.composePath = "nextcloud";
        };
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
        monitoring.restart.composePath = "wikijs";
      };
    };
  };

  # wildcard cert
  security.acme.certs."${wildcardCert}" = {
    domain = "*.${domain}";
    group = "nginx";
  };
}
