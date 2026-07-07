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
      };
    };
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

    systemd.tmpfiles.rules = [
      "d /var/lib/ktunnel 0700 ktunnel ktunnel - -"
    ];

    systemd.services = mapAttrs' (
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
          ExecStart = "${pkgs.ktunnel}/bin/ktunnel -p ${toString inst.tunnelPort} expose ${inst.serviceName} ${toString inst.localPort} --namespace ${inst.namespace} --server-image ${inst.image} --reuse";
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
    ) instances;
  };
}
