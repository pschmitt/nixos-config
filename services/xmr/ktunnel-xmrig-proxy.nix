{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrs'
    mkIf
    mkOption
    nameValuePair
    types
    ;

  cfg = config.services.ktunnel-xmrig-proxy;
  instances = lib.filterAttrs (_: inst: inst.enable) cfg;

  instanceOptions =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "ktunnel reverse-proxy to expose xmrig-proxy into a Kubernetes cluster";

        serviceName = mkOption {
          type = types.str;
          default = "xmrig-proxy";
          description = "Name of the Kubernetes Service to create.";
        };

        namespace = mkOption {
          type = types.str;
          default = "local-x";
          description = "Kubernetes namespace to deploy the ktunnel server pod into.";
        };

        localPort = mkOption {
          type = types.port;
          default = 3333;
          description = "Local xmrig-proxy port to forward cluster connections to.";
        };

        kubeconfig = mkOption {
          type = types.path;
          default = "/var/lib/ktunnel/kubeconfig-${name}";
          description = "Path to the kubeconfig for the target cluster.";
        };

        tunnelPort = mkOption {
          type = types.port;
          description = "Local port used for the ktunnel gRPC tunnel channel. Must be unique per instance.";
        };

        image = mkOption {
          type = types.str;
          default = "artifactory.prod.capp.wiit-cloud.io/docker-dockerio-remote/omrieival/ktunnel:v1.6.1";
          description = "ktunnel server image to deploy in the cluster (must be pullable from inside the cluster).";
        };

        user = mkOption {
          type = types.str;
          default = "ktunnel";
        };

        group = mkOption {
          type = types.str;
          default = "ktunnel";
        };

        restartInterval = mkOption {
          type = types.nullOr types.str;
          default = "12h";
          description = ''
            Blind safety-net restart interval for this ktunnel instance,
            as a systemd time span (e.g. "12h"). Set to null to disable.
            This is a coarse fallback on top of healthcheckInterval's
            active checking below — long enough to not be disruptive,
            short enough to bound worst-case downtime if the healthcheck
            itself were ever wrong.
          '';
        };

        healthcheckInterval = mkOption {
          type = types.nullOr types.str;
          default = "5min";
          description = ''
            How often to run an active end-to-end healthcheck for this
            ktunnel instance, as a systemd time span (e.g. "5min"). Set
            to null to disable.

            ktunnel's client can end up in a state where the process is
            alive and the systemd unit reports active, but its internal
            tunnel listener has silently died (observed: a stale session
            left over from --reuse-ing an existing server pod triggers
            "failed parsing session uuid from stream" followed by
            "closing listener on localhost:3333", after which every
            connection through the tunnel gets refused). That doesn't
            crash the process, so Restart=on-failure never fires.

            The healthcheck lists the current node names of this
            cluster's xmrig DaemonSet, then asks the shared xmrig-proxy's
            local /1/workers API whether at least one of them is
            connected and has reported in recently. If none have, the
            tunnel is treated as dead and
            ktunnel-xmrig-proxy-<name>.service is restarted.
          '';
        };
      };
    };

  restartServiceName = name: "ktunnel-xmrig-proxy-restart-${name}";
  restartableInstances = lib.filterAttrs (_: inst: inst.restartInterval != null) instances;

  healthcheckServiceName = name: "ktunnel-xmrig-proxy-healthcheck-${name}";
  healthcheckableInstances = lib.filterAttrs (_: inst: inst.healthcheckInterval != null) instances;

  # Considers a worker's last report stale after this long. Generous
  # relative to the 5min default healthcheckInterval so low-hashrate CPU
  # workers (which submit shares far less often than GPU ones) don't
  # trigger a false-positive restart.
  workerStaleAfterMs = 10 * 60 * 1000;

  healthcheckScript =
    name: inst:
    pkgs.writeShellScript "ktunnel-xmrig-proxy-healthcheck-${name}.sh" ''
      set -u
      export KUBECONFIG=${inst.kubeconfig}

      nodes_json=$(
        ${pkgs.kubectl}/bin/kubectl get pods -n ${inst.namespace} -l app=xmrig -o json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -c '[.items[].spec.nodeName] | unique' \
          || echo '[]'
      )
      workers_json=$(${pkgs.curl}/bin/curl -sf http://127.0.0.1:9674/1/workers 2>/dev/null || echo '{"workers":[]}')
      now_ms=$(($(date +%s%N) / 1000000))

      healthy=$(
        ${pkgs.jq}/bin/jq -r \
          --argjson nodes "$nodes_json" \
          --argjson now "$now_ms" \
          --argjson stale_after ${toString workerStaleAfterMs} '
          (.workers // []) as $ws
          | ($nodes // []) as $ns
          | ($ns | length) == 0
            or any($ns[]; . as $n | $ws | any(.[0] == $n and .[2] == 1 and (($now - .[7]) < $stale_after)))
        ' <<< "$workers_json"
      )

      if [ "$healthy" = "true" ]
      then
        echo "ktunnel-xmrig-proxy-${name}: at least one worker reachable (or no xmrig pods found yet), tunnel looks healthy"
        exit 0
      fi

      echo "ktunnel-xmrig-proxy-${name}: no worker for nodes $nodes_json reported in via the shared proxy in the last ${
        toString (workerStaleAfterMs / 60000)
      } minutes; tunnel looks dead, restarting" >&2
      exec ${pkgs.systemd}/bin/systemctl restart ktunnel-xmrig-proxy-${name}.service
    '';
in
{
  options.services.ktunnel-xmrig-proxy = mkOption {
    type = types.attrsOf (types.submodule instanceOptions);
    default = { };
    description = "ktunnel instances keyed by cluster name.";
  };

  config = mkIf (instances != { }) {
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

      services =
        mapAttrs' (
          name: inst:
          nameValuePair "ktunnel-xmrig-proxy-${name}" {
            description = "ktunnel: expose xmrig-proxy to k8s cluster (${name})";
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "xmrig-proxy.service"
            ];
            environment = {
              HOME = "/var/lib/ktunnel";
              KUBECONFIG = inst.kubeconfig;
            };
            serviceConfig = {
              User = inst.user;
              Group = inst.group;
              ExecStartPre = "-${pkgs.kubectl}/bin/kubectl --kubeconfig ${inst.kubeconfig} create namespace ${inst.namespace}";
              # No --reuse: reattaching to an existing server pod can hit a
              # ktunnel bug where a stale leftover session kills the client's
              # local tunnel listener without crashing the process (see
              # restartInterval above). Always provisioning a fresh
              # Service/Deployment on start avoids that failure mode entirely.
              ExecStart = "${pkgs.ktunnel}/bin/ktunnel -p ${toString inst.tunnelPort} expose ${inst.serviceName} ${toString inst.localPort} --namespace ${inst.namespace} --server-image ${inst.image}";
              Restart = "on-failure";
              RestartSec = "30s";
              # Hardening
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectHome = true;
              ProtectSystem = "strict";
              ReadWritePaths = [ "/var/lib/ktunnel" ];
              CapabilityBoundingSet = "";
              AmbientCapabilities = "";
            };
            wantedBy = [ "multi-user.target" ];
          }
        ) instances
        // mapAttrs' (
          name: inst:
          nameValuePair (restartServiceName name) {
            description = "Periodic self-restart of ktunnel-xmrig-proxy-${name} (self-healing watchdog)";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.systemd}/bin/systemctl restart ktunnel-xmrig-proxy-${name}.service";
            };
          }
        ) restartableInstances
        // mapAttrs' (
          name: inst:
          nameValuePair (healthcheckServiceName name) {
            description = "End-to-end healthcheck for ktunnel-xmrig-proxy-${name}, restarts it if dead";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = healthcheckScript name inst;
            };
          }
        ) healthcheckableInstances;

      timers =
        mapAttrs' (
          name: inst:
          nameValuePair (restartServiceName name) {
            description = "Periodically restart ktunnel-xmrig-proxy-${name}";
            timerConfig = {
              OnUnitActiveSec = inst.restartInterval;
              OnBootSec = inst.restartInterval;
              # Jitter so cluster-01/02 don't restart in lockstep.
              RandomizedDelaySec = "1h";
              Persistent = true;
            };
            wantedBy = [ "timers.target" ];
          }
        ) restartableInstances
        // mapAttrs' (
          name: inst:
          nameValuePair (healthcheckServiceName name) {
            description = "Periodically healthcheck ktunnel-xmrig-proxy-${name}";
            timerConfig = {
              OnUnitActiveSec = inst.healthcheckInterval;
              OnBootSec = inst.healthcheckInterval;
              # Jitter so cluster-01/02 don't both hit the shared proxy's
              # API at the same instant.
              RandomizedDelaySec = "1min";
              Persistent = true;
            };
            wantedBy = [ "timers.target" ];
          }
        ) healthcheckableInstances;
    };
  };
}
