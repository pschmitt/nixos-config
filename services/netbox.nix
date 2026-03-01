{
  config,
  lib,
  pkgs,
  ...
}:
let
  netboxHost = "netbox.${config.domains.main}";
in
{
  sops.secrets = {
    "netbox/secretKey" = {
      inherit (config.custom) sopsFile;
      owner = "netbox";
      group = "netbox";
      mode = "0400";
      restartUnits = [ "netbox.service" ];
    };
    # TODO once netbox 4.5 is available
    # https://netboxlabs.com/docs/netbox/configuration/required-parameters/#api_token_peppers
    # "netbox/apiTokenPeppers" = {
    #   inherit (config.custom) sopsFile;
    #   owner = "netbox";
    #   group = "netbox";
    #   mode = "0400";
    #   restartUnits = [ "netbox.service" ];
    # };
  };

  # TODO once netbox 4.5 is available on nixos-unstable
  # we should add apiTokenPeppersFile
  # https://github.com/NixOS/nixpkgs/pull/485109
  services = {
    netbox = {
      enable = true;
      package = pkgs.netbox-pr.netbox_4_5;
      listenAddress = "127.0.0.1";
      dataDir = "/mnt/data/srv/netbox";
      secretKeyFile = config.sops.secrets."netbox/secretKey".path;
      # apiTokenPeppersFile = config.sops.secrets."netbox/apiTokenPeppers".path;
      plugins = ps: [
        (ps.netbox-topology-views.overridePythonAttrs (_: {
          version = "4.5.0";
          src = pkgs.fetchFromGitHub {
            owner = "netbox-community";
            repo = "netbox-topology-views";
            tag = "v4.5.0";
            hash = "sha256-1KEkNfo++lX0uF0xS9JOyG7dQBQYYo2cSGkjicJ5+vE=";
          };
        }))
        (ps.netbox-documents.overridePythonAttrs (_: {
          version = "0.8.2";
          src = pkgs.fetchFromGitHub {
            owner = "jasonyates";
            repo = "netbox-documents";
            tag = "v0.8.2";
            hash = "sha256-XFVfNLU9a/0tQAVTrN2B1Oia/isOD8G5BdA3fVUn2sM=";
          };
        }))
      ];
      settings = {
        ALLOWED_HOSTS = [
          netboxHost
          "127.0.0.1"
        ];
        PLUGINS = [
          "netbox_documents"
          "netbox_topology_views"
        ];
      };
    };

    nginx.virtualHosts."${netboxHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations = {
        "/static/" = {
          alias = "${config.services.netbox.dataDir}/static/";
        };
        "/" = {
          proxyPass = "http://${config.services.netbox.listenAddress}:${toString config.services.netbox.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };

    monit.config = lib.mkAfter ''
      check host "netbox" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart netbox.service netbox-rq.service"
        if failed
          port ${toString config.services.netbox.port}
          protocol http
          request "/"
          with hostheader "${netboxHost}"
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  users.users.nginx.extraGroups = [ "netbox" ];

  # Fix permissions after UID changes (e.g., after reinstall)
  systemd.tmpfiles.rules = [
    "d ${config.services.netbox.dataDir} 0750 netbox netbox - -"
    "Z ${config.services.netbox.dataDir} 0750 netbox netbox - -"
  ];
}
