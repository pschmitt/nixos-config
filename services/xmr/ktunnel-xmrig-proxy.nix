{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    ;

  cfg = config.services.ktunnel-xmrig-proxy;
  instances = lib.filterAttrs (_: inst: inst.enable) cfg;

  ktunnelExpose = import ../ktunnel/expose.nix { inherit pkgs lib; };
  ktunnelHealthcheck = import ./ktunnel-healthcheck.nix { inherit pkgs; };

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
in
{
  options.services.ktunnel-xmrig-proxy = mkOption {
    type = types.attrsOf (types.submodule instanceOptions);
    default = { };
    description = "ktunnel instances keyed by cluster name.";
  };

  # NOTE: deliberately not `mkMerge (mapAttrsToList ... instances)` here.
  # mkMerge wrapping a list derived from `instances` (itself read from
  # config.services.ktunnel-xmrig-proxy) triggers a genuine infinite
  # recursion in the module system's `pushDownProperties` handling of the
  # mkMerge marker — reproduced with a trivial config body, so it's not
  # about anything ktunnelExpose does. Each instance's ktunnelExpose result
  # has uniquely-named systemd.services/timers keys, so a plain
  # recursiveUpdate fold is equivalent and doesn't trip the module system's
  # extra handling for mkMerge's "merge" marker.
  config =
    let
      base = import ../ktunnel/base.nix;
      perInstance = lib.mapAttrsToList (
        name: inst:
        ktunnelExpose {
          unitName = "ktunnel-xmrig-proxy-${name}";
          description = "ktunnel: expose xmrig-proxy to k8s cluster (${name})";
          inherit (inst)
            serviceName
            namespace
            localPort
            kubeconfig
            tunnelPort
            image
            user
            group
            restartInterval
            healthcheckInterval
            ;
          afterUnits = [ "xmrig-proxy.service" ];
          healthCheckScript = ktunnelHealthcheck.mkCheckScript name inst ktunnelHealthcheck.staleAfterMs;
        }
      ) instances;
    in
    mkIf (instances != { }) (
      base
      // {
        systemd = base.systemd // {
          services = lib.foldl' (a: b: a // b) { } (map (f: f.systemd.services or { }) perInstance);
          timers = lib.foldl' (a: b: a // b) { } (map (f: f.systemd.timers or { }) perInstance);
        };
      }
    );
}
