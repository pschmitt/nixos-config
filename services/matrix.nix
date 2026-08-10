{
  config,
  lib,
  pkgs,
  ...
}:
let
  matrixHost = "matrix.${config.domains.main}";
  elementHost = "element.${config.domains.main}";
  synapseDataDir = "/mnt/data/srv/matrix-synapse";
  synapseUser = "matrix-synapse";
  synapseGroup = "matrix-synapse";

  mkWellKnown = data: ''
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '${builtins.toJSON data}';
  '';
in
{
  sops = {
    secrets = {
      "matrix/registration-shared-secret" = config.custom.mkSecret {
        owner = synapseUser;
        group = synapseGroup;
        mode = "0400";
      };

      "matrix/mautrix-signal/encryption-pickle-key" = config.custom.mkSecret {
        owner = "mautrix-signal";
        group = "mautrix-signal";
        mode = "0400";
      };

      "matrix/mautrix-whatsapp/encryption-pickle-key" = config.custom.mkSecret {
        owner = "mautrix-whatsapp";
        group = "mautrix-whatsapp";
        mode = "0400";
      };

      "matrix/mautrix-meta-facebook/encryption-pickle-key" = config.custom.mkSecret {
        owner = "mautrix-meta-facebook";
        group = "mautrix-meta";
        mode = "0400";
      };
    };

    templates = {
      "matrix-synapse-secrets.yaml" = {
        content = ''
          database:
            name: psycopg2
            args:
              database: matrix-synapse
              user: ${synapseUser}
              host: /run/postgresql
            allow_unsafe_locale: true
          registration_shared_secret: ${config.sops.placeholder."matrix/registration-shared-secret"}
        '';
        owner = synapseUser;
        group = synapseGroup;
        mode = "0400";
        restartUnits = [ "matrix-synapse.service" ];
      };

      "mautrix-signal.env" = {
        content = ''
          ENCRYPTION_PICKLE_KEY=${config.sops.placeholder."matrix/mautrix-signal/encryption-pickle-key"}
        '';
        owner = "mautrix-signal";
        group = "mautrix-signal";
        mode = "0400";
        restartUnits = [ "mautrix-signal.service" ];
      };

      "mautrix-whatsapp.env" = {
        content = ''
          ENCRYPTION_PICKLE_KEY=${config.sops.placeholder."matrix/mautrix-whatsapp/encryption-pickle-key"}
        '';
        owner = "mautrix-whatsapp";
        group = "mautrix-whatsapp";
        mode = "0400";
        restartUnits = [ "mautrix-whatsapp.service" ];
      };

      "mautrix-meta-facebook.env" = {
        content = ''
          ENCRYPTION_PICKLE_KEY=${
            config.sops.placeholder."matrix/mautrix-meta-facebook/encryption-pickle-key"
          }
        '';
        owner = "mautrix-meta-facebook";
        group = "mautrix-meta";
        mode = "0400";
        restartUnits = [ "mautrix-meta-facebook.service" ];
      };
    };
  };

  services = {
    postgresql = {
      ensureDatabases = [ "matrix-synapse" ];
      ensureUsers = [
        {
          name = synapseUser;
          ensureDBOwnership = true;
        }
      ];
    };

    matrix-synapse = {
      enable = true;
      dataDir = synapseDataDir;
      extraConfigFiles = [ config.sops.templates."matrix-synapse-secrets.yaml".path ];
      settings = {
        server_name = matrixHost;
        public_baseurl = "https://${matrixHost}/";
        report_stats = false;
        enable_registration = false;
        url_preview_enabled = false;
        database = {
          name = "psycopg2";
          args = {
            database = "matrix-synapse";
            user = synapseUser;
            host = "/run/postgresql";
          };
        };
        listeners = [
          {
            port = 8008;
            bind_addresses = [ "127.0.0.1" ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [
              {
                names = [
                  "client"
                  "federation"
                ];
                compress = true;
              }
            ];
          }
        ];
      };
    };

    mautrix-signal = {
      enable = true;
      # Avoid the deprecated and insecure libolm dependency.  The pure-Go
      # implementation is experimental, but keeps the bridge off libolm.
      package = pkgs.mautrix-signal.override { withGoolm = true; };
      environmentFile = config.sops.templates."mautrix-signal.env".path;
      settings = {
        homeserver = {
          domain = matrixHost;
          address = "http://127.0.0.1:8008";
        };
        appservice.hostname = "127.0.0.1";
        bridge.permissions = {
          "*" = "relay";
          "${matrixHost}" = "user";
        };
        encryption = {
          allow = true;
          default = true;
          require = true;
          pickle_key = "$ENCRYPTION_PICKLE_KEY";
        };
        provisioning.shared_secret = "disable";
      };
    };

    mautrix-whatsapp = {
      enable = true;
      # Avoid the deprecated and insecure libolm dependency.  The pure-Go
      # implementation is experimental, but keeps the bridge off libolm.
      package = pkgs.mautrix-whatsapp.override { withGoolm = true; };
      environmentFile = config.sops.templates."mautrix-whatsapp.env".path;
      settings = {
        homeserver = {
          domain = matrixHost;
          address = "http://127.0.0.1:8008";
        };
        appservice.hostname = "127.0.0.1";
        bridge.permissions = {
          "*" = "relay";
          "${matrixHost}" = "user";
        };
        history_sync = {
          max_initial_conversations = -1;
          request_full_sync = true;
          full_sync_config.days_limit = 365;
        };
        backfill = {
          enabled = true;
          max_initial_messages = 50;
        };
        encryption = {
          allow = true;
          default = true;
          require = true;
          pickle_key = "$ENCRYPTION_PICKLE_KEY";
        };
        provisioning.shared_secret = "disable";
      };
    };

    mautrix-meta = {
      # Avoid the deprecated and insecure libolm dependency.  The pure-Go
      # implementation is experimental, but keeps the bridge off libolm.
      package = pkgs.mautrix-meta.override { withGoolm = true; };
      instances.facebook = {
        enable = true;
        environmentFile = config.sops.templates."mautrix-meta-facebook.env".path;
        settings = {
          homeserver = {
            domain = matrixHost;
            address = "http://127.0.0.1:8008";
          };
          appservice.hostname = "127.0.0.1";
          bridge.permissions = {
            "*" = "relay";
            "${matrixHost}" = "user";
          };
          encryption.pickle_key = "$ENCRYPTION_PICKLE_KEY";
        };
      };
    };

    nginx.virtualHosts = {
      "${matrixHost}" = {
        enableACME = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        locations = {
          "= /.well-known/matrix/server".extraConfig = mkWellKnown {
            "m.server" = "${matrixHost}:443";
          };
          "= /.well-known/matrix/client".extraConfig = mkWellKnown {
            "m.homeserver" = {
              base_url = "https://${matrixHost}";
            };
          };
          "/_matrix" = {
            proxyPass = "http://127.0.0.1:8008";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
          "/_synapse/client" = {
            proxyPass = "http://127.0.0.1:8008";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
          "/".extraConfig = "return 404;";
        };
      };

      "${elementHost}" = {
        enableACME = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        root = pkgs.element-web.override {
          conf = {
            default_server_config = {
              "m.homeserver" = {
                base_url = "https://${matrixHost}";
                server_name = matrixHost;
              };
            };
          };
        };
      };
    };

    monit.config = lib.mkAfter ''
      check host "matrix-synapse" with address "127.0.0.1"
        group services
        depends on postgresql
        if failed
          port 8008
          protocol http
          request "/_matrix/federation/v1/version"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 5 restarts within 15 cycles then alert
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${synapseDataDir} 0750 ${synapseUser} ${synapseGroup} - -"
  ];
}
