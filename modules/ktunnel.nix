# `ktunnel expose` instances: services.ktunnel.tunnels.<unit name> runs one
# tunnel as systemd unit <unit name>, with an optional safety-net restart timer
# and an optional active healthcheck timer. Shared by every ktunnel exposure
# module so all consumers get the same, battle-tested behavior instead of
# drifting apart.
#
# Deliberately does NOT pass `--reuse` to `ktunnel expose`: reattaching to an
# existing server pod can hit a ktunnel bug where a stale leftover session
# kills the client's local tunnel listener without crashing the process (the
# unit stays "active (running)" while every connection through the tunnel is
# silently refused). Always provisioning a fresh Service/Deployment on start
# avoids that failure mode entirely.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrsToList
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    types
    ;

  cfg = config.services.ktunnel;

  tunnelModule = {
    options = {
      description = mkOption {
        type = types.str;
        description = "Description of the tunnel's systemd unit.";
      };

      serviceName = mkOption {
        type = types.str;
        description = "Kubernetes Service name (`ktunnel expose <serviceName> ...`).";
      };

      namespace = mkOption {
        type = types.str;
        description = "Kubernetes namespace of the exposed Service.";
      };

      localPort = mkOption {
        type = types.port;
        description = "Local port the tunnel forwards to.";
      };

      kubeconfig = mkOption {
        type = types.str;
        description = "Path to the kubeconfig used for the cluster.";
      };

      tunnelPort = mkOption {
        type = types.port;
        description = "ktunnel's own port (`ktunnel -p`).";
      };

      image = mkOption {
        type = types.str;
        description = "ktunnel server image deployed into the cluster.";
      };

      user = mkOption {
        type = types.str;
        default = "ktunnel";
        description = "User the tunnel runs as.";
      };

      group = mkOption {
        type = types.str;
        default = "ktunnel";
        description = "Group the tunnel runs as.";
      };

      afterUnits = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "tinyproxy.service" ];
        description = "Units the tunnel starts after, e.g. the local service it forwards to.";
      };

      restartInterval = mkOption {
        type = types.nullOr types.str;
        default = "12h";
        description = ''
          Coarse safety-net restart (systemd time span); null disables it. A
          backstop on top of the healthcheck, not the primary defense against a
          dead tunnel.
        '';
      };

      healthcheckInterval = mkOption {
        type = types.nullOr types.str;
        default = "5min";
        description = "How often to run healthCheckScript (systemd time span); null disables it.";
      };

      healthCheckScript = mkOption {
        type = types.nullOr (types.either types.path types.package);
        default = null;
        description = ''
          Script that exits 0 when the tunnel looks healthy (or cannot be
          conclusively checked for an unrelated reason) and 1 when it looks
          dead. Required when healthcheckInterval is set.
        '';
      };
    };
  };

  restartName = unit: "${unit}-restart";
  healthcheckName = unit: "${unit}-healthcheck";

  kubectl = "${pkgs.kubectl}/bin/kubectl";

  tunnelServices =
    unit: t:
    {
      ${unit} = {
        inherit (t) description;
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ] ++ t.afterUnits;
        environment = {
          HOME = "/var/lib/ktunnel";
          KUBECONFIG = t.kubeconfig;
        };
        serviceConfig = {
          User = t.user;
          Group = t.group;
          ExecStartPre = [
            "-${kubectl} --kubeconfig ${t.kubeconfig} create namespace ${t.namespace}"
            # `ktunnel expose` always provisions a fresh Deployment/Service
            # (see the --reuse note above) and fails outright if one is
            # already there. A prior instance normally deletes its own on a
            # graceful stop, but an ungraceful exit (OOM, SIGKILL after
            # StopTimeout, host reboot) can leave one behind, which then
            # wedges every future start in a permanent AlreadyExists crash
            # loop -- Restart=on-failure and the healthcheck restart just
            # repeat the same failure forever. Deleting first makes startup
            # idempotent regardless of how the previous instance died.
            "-${kubectl} --kubeconfig ${t.kubeconfig} delete deployment,service ${t.serviceName} --namespace ${t.namespace} --ignore-not-found --wait --timeout=30s"
          ];
          ExecStart = "${pkgs.ktunnel}/bin/ktunnel -p ${toString t.tunnelPort} expose ${t.serviceName} ${toString t.localPort} --namespace ${t.namespace} --server-image ${t.image}";
          Restart = "on-failure";
          RestartSec = "30s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/ktunnel" ];
          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
        };
        wantedBy = [ "multi-user.target" ];
      };
    }
    // optionalAttrs (t.restartInterval != null) {
      ${restartName unit} = {
        description = "Periodic self-restart of ${unit} (self-healing watchdog)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl restart ${unit}.service";
        };
      };
    }
    // optionalAttrs (t.healthcheckInterval != null) {
      ${healthcheckName unit} = {
        description = "End-to-end healthcheck for ${unit}, restarts it if dead";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "${healthcheckName unit}-action.sh" ''
            if ${t.healthCheckScript}
            then
              exit 0
            fi
            echo "${unit}: restarting due to failed healthcheck" >&2
            exec ${pkgs.systemd}/bin/systemctl restart ${unit}.service
          '';
        };
      };
    };

  # NOTE: deliberately no OnBootSec here. On a host that's been up longer
  # than the interval (the common case -- these timers get freshly created
  # by a `nixos-rebuild switch` on an already-running box, not by an actual
  # reboot), OnBootSec's deadline is already in the past the moment the timer
  # is activated, so systemd fires it immediately. That raced with the main
  # service's own first startup (kill mid-`ktunnel expose`, retry, hit
  # "already exists") and would happen again on every deploy that touches
  # these units. OnUnitActiveSec alone still guarantees a first run after the
  # interval from whenever the timer actually starts, and Persistent=true
  # still catches up after a real reboot.
  tunnelTimers =
    unit: t:
    optionalAttrs (t.restartInterval != null) {
      ${restartName unit} = {
        description = "Periodically restart ${unit}";
        timerConfig = {
          OnUnitActiveSec = t.restartInterval;
          # Jitter so multiple instances on the same host don't restart in lockstep.
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };
    }
    // optionalAttrs (t.healthcheckInterval != null) {
      ${healthcheckName unit} = {
        description = "Periodically healthcheck ${unit}";
        timerConfig = {
          OnUnitActiveSec = t.healthcheckInterval;
          RandomizedDelaySec = "1min";
          Persistent = true;
        };
        wantedBy = [ "timers.target" ];
      };
    };
in
{
  options.services.ktunnel.tunnels = mkOption {
    type = types.attrsOf (types.submodule tunnelModule);
    default = { };
    description = "`ktunnel expose` instances, keyed by systemd unit name.";
  };

  config = mkIf (cfg.tunnels != { }) {
    assertions = mapAttrsToList (unit: t: {
      assertion = t.healthcheckInterval == null || t.healthCheckScript != null;
      message = "services.ktunnel.tunnels.${unit}: healthCheckScript is required when healthcheckInterval is set.";
    }) cfg.tunnels;

    users.groups.ktunnel = { };
    users.users.ktunnel = {
      group = "ktunnel";
      isSystemUser = true;
      description = "ktunnel k8s tunnel service account";
    };

    systemd = {
      tmpfiles.rules = [
        "d /var/lib/ktunnel 0700 ktunnel ktunnel - -"
      ];
      services = mkMerge (mapAttrsToList tunnelServices cfg.tunnels);
      timers = mkMerge (mapAttrsToList tunnelTimers cfg.tunnels);
    };
  };
}
