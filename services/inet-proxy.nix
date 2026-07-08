{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    filterAttrs
    mapAttrsToList
    mkIf
    mkOption
    types
    ;

  cfg = config.services.inet-proxy;
  enabledClusters = filterAttrs (_: inst: inst.enable) cfg.clusters;

  ktunnelExpose = import ./ktunnel/expose.nix { inherit pkgs lib; };
  inetProxyHealthcheck = import ./ktunnel/inet-proxy-healthcheck.nix { inherit pkgs; };

  # LoadBalancer Service manifest (requires MetalLB or equivalent)
  lbManifest =
    inst:
    pkgs.writeText "inet-proxy-lb.yaml" ''
      apiVersion: v1
      kind: Service
      metadata:
        name: ${inst.serviceName}-lb
        namespace: ${inst.namespace}
        annotations:
          metallb.universe.tf/address-pool: ${inst.lbPool}
      spec:
        type: LoadBalancer
        selector:
          app.kubernetes.io/instance: ${inst.serviceName}
          app.kubernetes.io/name: ${inst.serviceName}
        ports:
          - name: http-proxy
            port: ${toString cfg.port}
            targetPort: ${toString cfg.port}
    '';

  # Fallback NodePort Service manifest (no MetalLB)
  nodePortManifest =
    inst:
    pkgs.writeText "inet-proxy-nodeport.yaml" ''
      apiVersion: v1
      kind: Service
      metadata:
        name: ${inst.serviceName}-nodeport
        namespace: ${inst.namespace}
      spec:
        type: NodePort
        selector:
          app.kubernetes.io/instance: ${inst.serviceName}
          app.kubernetes.io/name: ${inst.serviceName}
        ports:
          - name: http-proxy
            port: ${toString cfg.port}
            targetPort: ${toString cfg.port}
            nodePort: ${toString inst.nodePort}
    '';

  externalManifests =
    inst:
    lib.optional (inst.lbPool != null) (lbManifest inst)
    ++ lib.optional (inst.nodePort != null) (nodePortManifest inst);

  clusterOptions =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "ktunnel exposure to this cluster";

        serviceName = mkOption {
          type = types.str;
          default = "inet-proxy";
          description = "Name of the Kubernetes Service ktunnel creates.";
        };

        namespace = mkOption {
          type = types.str;
          default = "inet-proxy";
          description = "Kubernetes namespace to deploy the ktunnel server pod into.";
        };

        kubeconfig = mkOption {
          type = types.path;
          default = "/var/lib/ktunnel/kubeconfig-${name}";
          description = "Path to the kubeconfig for the target cluster.";
        };

        tunnelPort = mkOption {
          type = types.port;
          description = "Port used for the ktunnel gRPC control channel. Must be unique per instance.";
        };

        lbPool = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "MetalLB address-pool name for a LoadBalancer Service. Preferred over nodePort when MetalLB is available.";
        };

        nodePort = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Fallback: expose the proxy on this NodePort on every k8s node. Use lbPool instead when MetalLB is available.";
        };

        image = mkOption {
          type = types.str;
          default = "artifactory.prod.capp.wiit-cloud.io/docker-dockerio-remote/omrieival/ktunnel:v1.6.1";
          description = "ktunnel server image pullable from inside the cluster.";
        };

        restartInterval = mkOption {
          type = types.nullOr types.str;
          default = "12h";
          description = ''
            Coarse safety-net restart interval for this ktunnel instance, as a
            systemd time span (e.g. "12h"). Set to null to disable. This is a
            backstop on top of healthcheckInterval below, not the primary
            defense against a dead tunnel.
          '';
        };

        healthcheckInterval = mkOption {
          type = types.nullOr types.str;
          default = "5min";
          description = ''
            How often to run an active end-to-end healthcheck for this
            ktunnel instance, as a systemd time span (e.g. "5min"). Set to
            null to disable.

            The check runs a real HTTPS request through
            kubectl port-forward -> ktunnel server pod -> gRPC tunnel ->
            local tinyproxy -> internet, and restarts the tunnel if that
            fails. See services/ktunnel/inet-proxy-healthcheck.nix.
          '';
        };
      };
    };
in
{
  options.services.inet-proxy = {
    enable = lib.mkEnableOption "HTTP forward proxy (tinyproxy) exposed to Kubernetes clusters via ktunnel";

    port = mkOption {
      type = types.port;
      default = 3128;
      description = "Local port tinyproxy listens on.";
    };

    clusters = mkOption {
      type = types.attrsOf (types.submodule clusterOptions);
      default = { };
      description = "Clusters to expose the proxy into, keyed by cluster name.";
    };
  };

  # NOTE: deliberately not mkMerge/recursiveUpdate here — either one wrapping
  # values derived from `cfg`/`enabledClusters` (both read from
  # config.services.inet-proxy) triggers a genuine infinite recursion in this
  # nixpkgs' module system (reproduced with trivial config bodies, so it's
  # not about anything ktunnelExpose does; see the identical note in
  # services/xmr/ktunnel-xmrig-proxy.nix). Every instance's ktunnelExpose
  # result has uniquely-named systemd.services/timers keys, so plain shallow
  # `//` at each level is equivalent and doesn't trip it.
  config =
    let
      base = import ./ktunnel/base.nix;

      perInstance = mapAttrsToList (
        name: inst:
        let
          unitName = "ktunnel-inet-proxy-${name}";
          # Scratch port for the healthcheck's transient `kubectl port-forward`;
          # offset from tunnelPort (already required unique per instance) so it
          # can't collide with it or with another instance's check.
          checkPort = inst.tunnelPort + 1;
          expose = ktunnelExpose {
            inherit unitName;
            description = "ktunnel: expose inet-proxy to k8s cluster (${name})";
            inherit (inst)
              serviceName
              namespace
              kubeconfig
              tunnelPort
              image
              restartInterval
              healthcheckInterval
              ;
            localPort = cfg.port;
            afterUnits = [ "tinyproxy.service" ];
            healthCheckScript = inetProxyHealthcheck.mkCheckScript name {
              inherit (inst) kubeconfig namespace serviceName;
              inherit (cfg) port;
              inherit checkPort;
            };
          };
        in
        expose
        // {
          systemd = expose.systemd // {
            services = expose.systemd.services // {
              "${unitName}" = expose.systemd.services."${unitName}" // {
                serviceConfig = expose.systemd.services."${unitName}".serviceConfig // {
                  ExecStartPost = map (
                    manifest: "${pkgs.kubectl}/bin/kubectl --kubeconfig ${inst.kubeconfig} apply -f ${manifest}"
                  ) (externalManifests inst);
                };
              };
            };
          };
        }
      ) enabledClusters;
    in
    mkIf cfg.enable (
      base
      // {
        services.tinyproxy = {
          enable = true;
          settings = {
            Port = cfg.port;
            Listen = "127.0.0.1";
            Timeout = 600;
            # ktunnel connects from localhost, so this is the only source address
            Allow = [
              "127.0.0.1"
              "::1"
            ];
            MaxClients = 100;
            DisableViaHeader = true;
            LogLevel = "Warning";
          };
        };
        systemd = base.systemd // {
          services = lib.foldl' (a: b: a // b) { } (map (f: f.systemd.services or { }) perInstance);
          timers = lib.foldl' (a: b: a // b) { } (map (f: f.systemd.timers or { }) perInstance);
        };
      }
    );
}
