{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    filterAttrs
    mapAttrs'
    mkIf
    mkOption
    nameValuePair
    types
    ;

  cfg = config.services.inet-proxy;
  enabledClusters = filterAttrs (_: inst: inst.enable) cfg.clusters;

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

  config = mkIf cfg.enable {
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

    users.groups.ktunnel = { };
    users.users.ktunnel = {
      group = "ktunnel";
      isSystemUser = true;
      description = "ktunnel k8s tunnel service account";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/ktunnel 0700 ktunnel ktunnel - -"
    ];

    systemd.services = mapAttrs' (
      name: inst:
      nameValuePair "ktunnel-inet-proxy-${name}" {
        description = "ktunnel: expose inet-proxy to k8s cluster (${name})";
        wants = [ "network-online.target" ];
        after = [
          "network-online.target"
          "tinyproxy.service"
        ];
        environment = {
          HOME = "/var/lib/ktunnel";
          KUBECONFIG = inst.kubeconfig;
        };
        serviceConfig = {
          User = "ktunnel";
          Group = "ktunnel";
          ExecStartPre = "-${pkgs.kubectl}/bin/kubectl --kubeconfig ${inst.kubeconfig} create namespace ${inst.namespace}";
          ExecStart = "${pkgs.ktunnel}/bin/ktunnel -p ${toString inst.tunnelPort} expose ${inst.serviceName} ${toString cfg.port} --namespace ${inst.namespace} --server-image ${inst.image} --reuse";
          ExecStartPost = map (
            manifest: "${pkgs.kubectl}/bin/kubectl --kubeconfig ${inst.kubeconfig} apply -f ${manifest}"
          ) (externalManifests inst);
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
      }
    ) enabledClusters;
  };
}
