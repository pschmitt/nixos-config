{
  config,
  lib,
  pkgs,
  ...
}:
let
  netboxHost = "netbox.${config.domains.main}";
  netboxBind = "127.0.0.1:8001";
  netboxPort = 8001;
in
{
  sops.secrets = {
    "netbox/secretKey" = config.custom.mkSecret {
      owner = "netbox";
      group = "netbox";
      mode = "0400";
      restartUnits = [ "netbox.service" ];
    };
    "netbox/apiTokenPeppers" = config.custom.mkSecret {
      owner = "netbox";
      group = "netbox";
      mode = "0400";
      restartUnits = [ "netbox.service" ];
    };
  };

  services = {
    netbox = {
      enable = true;
      package = pkgs.master.netbox;
      bind = netboxBind;
      dataDir = "/mnt/data/srv/netbox";
      secretKeyFile = config.sops.secrets."netbox/secretKey".path;
      apiTokenPepperFiles."1" = config.sops.secrets."netbox/apiTokenPeppers".path;
      plugins = ps: [
        (ps.netbox-documents.overridePythonAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace netbox_documents/forms.py \
              --replace "list(DocTypeChoices.choices)" "list(DocTypeChoices)"
          '';
        }))
        ps.netbox-interface-synchronization
        ps.netbox-qrcode
        ps.netbox-topology-views
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
          proxyPass = "http://${netboxBind}";
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
          port ${toString netboxPort}
          protocol http
          request "/"
          with hostheader "${netboxHost}"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };

  users.users.nginx.extraGroups = [ "netbox" ];

  # Fix permissions after UID changes (e.g., after reinstall)
  systemd.tmpfiles.rules = [
    "d ${config.services.netbox.dataDir} 0750 netbox netbox - -"
    "Z ${config.services.netbox.dataDir} 0750 netbox netbox - -"
  ];
}
