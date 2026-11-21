{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.stalwart.provision;
  stalwart = config.services.stalwart;
in
{
  options.services.stalwart.provision = {
    enable = lib.mkEnableOption "Stalwart Configuration Provisioning";
    runtimePlan = lib.mkOption {
      default = null;
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            file = lib.mkOption {
              type = lib.types.str;
              description = "Runtime path to an NDJSON provisioning plan.";
            };
            usernameFile = lib.mkOption {
              type = lib.types.str;
              description = "Runtime path to the provisioning account username.";
            };
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = "Runtime path to the provisioning account password.";
            };
            secretFiles = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Runtime files used to substitute $stalwartSecret references in the plan.";
            };
            requiredFields = lib.mkOption {
              type = lib.types.attrsOf (lib.types.attrsOf lib.types.json);
              default = { };
              description = "Existing field values that must match before provisioning objects of each type.";
            };
          };
        }
      );
      description = "Supply a private plan and account credentials through systemd credentials.";
    };
    enterprise = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow enterprise-only settings";
    };
    package = lib.mkPackageOption pkgs "stalwart-cli" { };
    reloadSettings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tell Stalwart to reload its settings when complete";
    };
    urls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "The URLs of the Stalwart instance to provision onto. If multiple URLs are specified, they will be cycled through until one succeeds.";
    };
    timeout = lib.mkOption {
      type = lib.types.nullOr lib.types.numbers.positive;
      default = null;
      example = 300;
      description = "Timeout after this many seconds.";
    };

    singletons = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.json;
      default = { };
      description = "Singletons to configure.";
      example = {
        SystemSettings = {
          defaultHostname = "mail.example.com";
          defaultDomainId = "#mainDomain";
        };
      };
    };
    objects = lib.mkOption {
      type = lib.types.lazyAttrsOf (
        lib.types.submodule {
          options = {
            reconcile = lib.mkOption {
              type = lib.types.bool;
              description = ''
                Whether to use the `reconcile` operation instead of `upsert`, deleting objects in this set that are not explicitly defined.
                Read the [documentation](https://stalw.art/docs/management/cli/apply/#reconciling-to-exact-state) for more information.
              '';
              default = false;
            };

            match = lib.mkOption {
              type = lib.types.nullOr (lib.types.either (lib.types.listOf lib.types.str) lib.types.str);
              apply = v: if lib.isList v then lib.uniqueStrings v else v;
              description = ''
                The fields to match on, a wildcard (`"*"`), or null.
                Read the [documentation](https://stalw.art/docs/management/cli/apply/#upsert) for more information.
              '';
              example = [ "name" ];
              default = null;
            };

            scope = lib.mkOption {
              type = lib.types.nullOr lib.types.json;
              description = ''
                Optional scope to restrict which objects this operation can affect.
                Should be a partial value of the object type.
                This is especially useful when `reconcile` is `true`, only objects that match the scope will be considered for deletion.
                Read the [documentation](https://stalw.art/docs/management/cli/apply/#scoping-an-operation-with-scope) for more information.
              '';
            };

            objects = lib.mkOption {
              type = lib.types.lazyAttrsOf lib.types.json;
              description = "The objects in the set. Attribute names define IDs that can be referenced with `#name` elsewhere where an ID is expected.";
            };
          };
        }
      );
      default = { };
      description = "Objects to configure.";
      example = {
        NetworkListener = {
          reconcile = false;
          match = [ "name" ];
          objects = {
            nl-mgmt = {
              name = "management";
              protocol = "http";
              bind = [ "[::]:8080" ];
            };
            nl-inc = {
              name = "incoming";
              protocol = "submissions";
              bind = [ "[::]:465" ];
              implicitTls = true;
            };
          };
        };
        Domain = {
          reconcile = true;
          match = [ "name" ];
          objects = {
            mainDomain = {
              name = "mail.example.com";
              certificateManagement."@type" = "Manual";
              dkimManagement."@type" = "Manual";
              dnsManagement."@type" = "Manual";
              subAddressing."@type" = "Enabled";
            };
          };
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.runtimePlan != null) {
      assertions = [
        {
          assertion = stalwart.enable && lib.versionAtLeast stalwart.package.version "0.16";
          message = "Stalwart runtime provisioning requires an enabled Stalwart 0.16 or newer service.";
        }
        {
          assertion = cfg.objects == { } && cfg.singletons == { } && cfg.urls != [ ];
          message = "Stalwart runtime provisioning requires an endpoint and a single runtime plan.";
        }
      ];

      systemd.services.stalwart-provision = {
        description = "Apply the Stalwart provisioning plan";
        wantedBy = [ "multi-user.target" ];
        requires = [ "stalwart.service" ];
        after = [
          "stalwart.service"
          "sops-nix.service"
        ];
        partOf = [ "stalwart.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = stalwart.user;
          Group = stalwart.group;
          RuntimeDirectory = "stalwart-provision";
          Environment = [
            "HOME=/run/stalwart-provision"
          ]
          ++ lib.optional cfg.reloadSettings "STALWART_RELOAD_SETTINGS=1";
          LoadCredential = [
            "plan:${cfg.runtimePlan.file}"
            "username:${cfg.runtimePlan.usernameFile}"
            "password:${cfg.runtimePlan.passwordFile}"
          ]
          ++ lib.mapAttrsToList (name: path: "plan-secret-${name}:${path}") cfg.runtimePlan.secretFiles
          ++
            lib.optional (cfg.runtimePlan.requiredFields != { })
              "required-fields:${
                (pkgs.formats.json { }).generate "stalwart-required-fields.json" cfg.runtimePlan.requiredFields
              }";
          TimeoutStartSec = if cfg.timeout == null then 120 else cfg.timeout;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ExecStart =
            let
              provision = pkgs.writeShellApplication {
                name = "stalwart-runtime-provision";
                runtimeInputs = [
                  cfg.package
                  pkgs.coreutils
                  pkgs.curl
                  pkgs.jq
                ];
                text = builtins.readFile ../scripts/stalwart-provision.sh;
              };
            in
            "${lib.getExe provision} ${lib.escapeShellArgs cfg.urls}";
        };
      };
    })
    (lib.mkIf (cfg.enable && cfg.runtimePlan == null) (
      let
        variant = type: value: { "@type" = type; } // value;

        plans =
          lib.mapAttrsToList (
            name: value:
            variant "update" {
              object = name;
              inherit value;
            }
          ) cfg.singletons
          ++ lib.mapAttrsToList (
            name: value:
            variant (if value.reconcile then "reconcile" else "upsert") {
              object = name;
              matchOn = value.match;
              inherit (value) scope;
              value = value.objects;
            }
          ) cfg.objects;

        unsorted = lib.concatMapStringsSep "\n" builtins.toJSON plans;

        sorted =
          pkgs.runCommand "stalwart-provision.ndjson"
            {
              nativeBuildInputs = with pkgs.lua52Packages; [
                lua
                dkjson
              ];
            }
            ''
              gzip -d ${stalwart.package.src}/resources/schema/${
                if lib.versionAtLeast stalwart.package.version "1" && !cfg.enterprise then
                  "schema_oss"
                else
                  "schema"
              }.json.gz -c > ./schema.json
              lua ${./provision-check-sort.lua} ${lib.escapeShellArg unsorted} $out ./schema.json ${lib.optionalString cfg.reloadSettings "--reload"}
            '';
      in
      {
        assertions = [
          {
            assertion = stalwart.enable;
            message = "<option>services.stalwart.provision</option> requires <option>services.stalwart.enable</option> to be true";
          }
          {
            assertion = stalwart.admin.enable;
            message = "<option>services.stalwart.provision</option> requires <option>services.stalwart.admin.enable</option> to be true";
          }
          {
            assertion = lib.versionAtLeast stalwart.package.version "0.16";
            message = "<option>services.stalwart.provision</option> requires <option>services.stalwart.package</option> to be at least version 0.16";
          }
        ];

        systemd.services.stalwart-provision = {
          description = "Stalwart Configuration Provisioning";
          wantedBy = [ "multi-user.target" ];
          partOf = [ "stalwart.service" ];
          after = [ "stalwart.service" ];
          bindsTo = [ "stalwart.service" ];
          serviceConfig = {
            Type = "oneshot";
            LoadCredential = config.systemd.services.stalwart.serviceConfig.LoadCredential;
            TimeoutSec = lib.mkIf (cfg.timeout != null) cfg.timeout;

            # stalwart does not currently notify systemd that it has started
            # see https://github.com/stalwartlabs/stalwart/pull/2383
            ExecStart = pkgs.writeShellScript "stalwart-provision" ''
              while :; do
                for url in ${lib.join " " (map lib.escapeShellArg cfg.urls)}; do
                  if ${pkgs.curl}/bin/curl --fail $url/healthz/live &>/dev/null; then
                    echo "connection to $url succeeded, attempting to provision onto it"
                    STALWART_URL=$url STALWART_PASSWORD=`systemd-creds cat ${stalwart.admin.username}` ${lib.getExe cfg.package} apply --file ${sorted}
                    exit
                  fi
                  sleep 0.25
                done
              done
            '';
            Environment = [
              "STALWART_USER=${lib.escapeShellArg stalwart.admin.username}"
            ];
          };
        };
      }
    ))
  ];
}
