# Shared implementation for one `ktunnel expose` instance: the systemd
# service that runs the tunnel, an optional safety-net restart timer, and an
# optional active healthcheck timer. Used internally by services/inet-proxy.nix
# and services/xmr/ktunnel-xmrig-proxy.nix so both get the same, correctly
# battle-tested behavior instead of drifting apart.
#
# Deliberately does NOT pass `--reuse` to `ktunnel expose`: reattaching to an
# existing server pod can hit a ktunnel bug where a stale leftover session
# kills the client's local tunnel listener without crashing the process (the
# unit stays "active (running)" while every connection through the tunnel is
# silently refused). Always provisioning a fresh Service/Deployment on start
# avoids that failure mode entirely — this is what
# services/xmr/ktunnel-xmrig-proxy.nix already switched to (see git history:
# "ktunnel-xmrig-proxy: drop --reuse, add active healthcheck + safety-net
# restart"); services/inet-proxy.nix used to still have --reuse plus a blind
# `RuntimeMaxSec=600s` restart-every-10-minutes hammer as a workaround for the
# same underlying bug, which is what this shared module replaces.
{ pkgs, lib }:
{
  # Base name for the generated systemd units, e.g. "ktunnel-inet-proxy-cluster-02"
  # or "ktunnel-xmrig-proxy-cluster-01". Kept caller-controlled (rather than
  # derived here) since ktunnel-xmrig-proxy's exact unit-name pattern is
  # depended on externally by modules/home-manager/xmr-mining.nix.
  unitName,
  description,

  # `ktunnel expose <serviceName> <localPort> --namespace <namespace> ...`
  serviceName,
  namespace,
  localPort,
  kubeconfig,
  tunnelPort,
  image,

  user ? "ktunnel",
  group ? "ktunnel",

  # Extra unit names this tunnel should start after (e.g. the local service
  # it forwards to, such as "tinyproxy.service" or "xmrig-proxy.service").
  afterUnits ? [ ],

  # Coarse safety-net restart, as a systemd time span (e.g. "12h"). Set to
  # null to disable. This is a backstop on top of the healthcheck below, not
  # the primary defense against a dead tunnel.
  restartInterval ? "12h",

  # How often to run `healthCheckScript`, as a systemd time span (e.g.
  # "5min"). Set to null (together with healthCheckScript = null) to disable
  # active health-checking entirely.
  healthcheckInterval ? "5min",

  # A pkgs.writeShellScript (or equivalent derivation) that exits 0 when the
  # tunnel looks healthy (or can't be conclusively checked for an unrelated
  # reason) and 1 when it looks dead. Required when healthcheckInterval != null.
  healthCheckScript ? null,
}:
let
  restartServiceName = "${unitName}-restart";
  healthcheckServiceName = "${unitName}-healthcheck";

  healthcheckRestartScript = pkgs.writeShellScript "${healthcheckServiceName}-action.sh" ''
    if ${healthCheckScript}
    then
      exit 0
    fi
    echo "${unitName}: restarting due to failed healthcheck" >&2
    exec ${pkgs.systemd}/bin/systemctl restart ${unitName}.service
  '';
in
{
  systemd = {
    services = {
      "${unitName}" = {
        inherit description;
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ] ++ afterUnits;
        environment = {
          HOME = "/var/lib/ktunnel";
          KUBECONFIG = kubeconfig;
        };
        serviceConfig = {
          User = user;
          Group = group;
          ExecStartPre = "-${pkgs.kubectl}/bin/kubectl --kubeconfig ${kubeconfig} create namespace ${namespace}";
          ExecStart = "${pkgs.ktunnel}/bin/ktunnel -p ${toString tunnelPort} expose ${serviceName} ${toString localPort} --namespace ${namespace} --server-image ${image}";
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
    // lib.optionalAttrs (restartInterval != null) {
      "${restartServiceName}" = {
        description = "Periodic self-restart of ${unitName} (self-healing watchdog)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl restart ${unitName}.service";
        };
      };
    }
    // lib.optionalAttrs (healthcheckInterval != null) {
      "${healthcheckServiceName}" = {
        description = "End-to-end healthcheck for ${unitName}, restarts it if dead";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = healthcheckRestartScript;
        };
      };
    };

    # NOTE: deliberately no OnBootSec here. On a host that's been up longer
    # than the interval (the common case — these timers get freshly created
    # by a `nixos-rebuild switch` on an already-running box, not by an
    # actual reboot), OnBootSec's deadline is already in the past the moment
    # the timer is activated, so systemd fires it immediately. That raced
    # with the main service's own first startup here (kill mid-`ktunnel
    # expose`, retry, hit "already exists") and would happen again on every
    # future deploy that touches these units. OnUnitActiveSec alone still
    # guarantees a first run after `restartInterval`/`healthcheckInterval`
    # from whenever the timer actually starts, and Persistent=true still
    # catches up after a real reboot.
    timers =
      lib.optionalAttrs (restartInterval != null) {
        "${restartServiceName}" = {
          description = "Periodically restart ${unitName}";
          timerConfig = {
            OnUnitActiveSec = restartInterval;
            # Jitter so multiple instances on the same host don't restart in lockstep.
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };
      }
      // lib.optionalAttrs (healthcheckInterval != null) {
        "${healthcheckServiceName}" = {
          description = "Periodically healthcheck ${unitName}";
          timerConfig = {
            OnUnitActiveSec = healthcheckInterval;
            RandomizedDelaySec = "1min";
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };
      };
  };
}
