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
    "netbox/apiTokenPeppers" = {
      inherit (config.custom) sopsFile;
      owner = "netbox";
      group = "netbox";
      mode = "0400";
      restartUnits = [ "netbox.service" ];
    };
  };

  services = {
    netbox = {
      enable = true;
      package = pkgs.netbox;
      listenAddress = "127.0.0.1";
      dataDir = "/mnt/data/srv/netbox";
      secretKeyFile = config.sops.secrets."netbox/secretKey".path;
      apiTokenPeppersFile = config.sops.secrets."netbox/apiTokenPeppers".path;
      plugins =
        ps: with ps; [
          netbox-documents
          netbox-interface-synchronization
          netbox-qrcode
          netbox-topology-views
        ];
      settings = {
        ALLOWED_HOSTS = [
          netboxHost
          "127.0.0.1"
        ];
        PLUGINS = [
          "netbox_documents"
          "netbox_interface_synchronization"
          "netbox_qrcode"
          "netbox_topology_views"
        ];
      };
      extraConfig = ''
        PLUGINS_CONFIG = {
            'netbox_documents': {
                'documents_location': 'right',
                'allowed_doc_types': {
                    '__all__': [
                        'manual',
                        'purchaseorder',
                        'floorplan',
                        'supportcontract',
                        'other',
                    ],
                },
            },
            'netbox_interface_synchronization': {},
            'netbox_qrcode': {
                'device': {
                    'label_height': '12mm',
                    'label_qr_width': '10mm',
                    'label_qr_height': '10mm',
                    'label_qr_text_distance': '0.5mm',
                    'label_edge_top': '0.5mm',
                    'label_edge_bottom': '0.5mm',
                    'label_edge_left': '1mm',
                    'label_edge_right': '0.5mm',
                    'font_size': '2mm',
                    'text_fields': ['name', 'asset_tag', 'serial'],
                },
            },
        }
      '';
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
