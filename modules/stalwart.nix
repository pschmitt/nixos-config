{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.stalwart;
  networkListenerObjects = lib.mapAttrs' (
    logicalName: listener:
    let
      objectName = if listener.name == null then logicalName else listener.name;
    in
    {
      name = logicalName;
      value = {
        name = objectName;
        inherit (listener) protocol tlsImplicit;
        bind = builtins.listToAttrs (
          map (address: {
            name = address;
            value = true;
          }) listener.bind
        );
      };
    }
  ) cfg.networkListeners;
  networkListenerPlan = pkgs.writeText "stalwart-network-listeners.ndjson" (
    builtins.toJSON {
      "@type" = "reconcile";
      object = "NetworkListener";
      matchOn = [ "name" ];
      value = networkListenerObjects;
    }
  );
  networkListenerConfigure = pkgs.writeShellApplication {
    name = "stalwart-network-listener-configure";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.stalwart-cli
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/stalwart-network-listener-configure.sh;
  };
in
{
  options.custom.stalwart = {
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/stalwart/config.json";
      description = "Stalwart bootstrap configuration file used by the declarative reconciler.";
    };

    recoveryUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8080";
      description = "URL of the temporary Stalwart recovery listener.";
    };

    networkListeners = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Persistent Stalwart object name; defaults to the attribute name.";
            };

            bind = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Socket addresses for this Stalwart listener.";
            };

            protocol = lib.mkOption {
              type = lib.types.str;
              description = "Stalwart listener protocol.";
            };

            tlsImplicit = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether this listener expects implicit TLS.";
            };
          };
        }
      );
      default = { };
      description = "Declarative Stalwart NetworkListener objects managed through stalwart-cli.";
    };
  };

  config = lib.mkIf (cfg.networkListeners != { }) {
    assertions = [
      {
        assertion = config.services.stalwart.enable;
        message = "custom.stalwart.networkListeners requires services.stalwart.enable";
      }
    ];

    systemd.services.stalwart-network-config = {
      description = "Apply declarative Stalwart network listeners";
      wantedBy = [ "multi-user.target" ];
      wants = [ "stalwart.service" ];
      after = [ "stalwart.service" ];
      restartTriggers = [ networkListenerPlan ];
      restartIfChanged = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${networkListenerConfigure}/bin/stalwart-network-listener-configure ${networkListenerPlan} ${config.services.stalwart.package}/bin/stalwart ${cfg.configFile} ${cfg.recoveryUrl}";
      };
    };
  };
}
