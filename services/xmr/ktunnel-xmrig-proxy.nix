{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;
  cfg = config.services.ktunnel-xmrig-proxy;
in
{
  options.services.ktunnel-xmrig-proxy = {
    enable = mkEnableOption "ktunnel reverse-proxy to expose xmrig-proxy into a Kubernetes cluster";

    serviceName = mkOption {
      type = types.str;
      default = "xmrig-proxy";
      description = "Name of the Kubernetes Service to create.";
    };

    namespace = mkOption {
      type = types.str;
      default = "xmr";
      description = "Kubernetes namespace to deploy the ktunnel server pod into.";
    };

    localPort = mkOption {
      type = types.port;
      default = 3333;
      description = "Local xmrig-proxy port to forward cluster connections to.";
    };

    kubeconfig = mkOption {
      type = types.path;
      default = "/var/lib/ktunnel-wiit/kubeconfig";
      description = "Path to the kubeconfig for the target cluster.";
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

  config = mkIf cfg.enable {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      inherit (cfg) group;
      isSystemUser = true;
      description = "ktunnel k8s tunnel service account";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/ktunnel-wiit 0700 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.ktunnel-wiit-xmrig-proxy = {
      description = "ktunnel: expose xmrig-proxy to k8s cluster (wiit-edge-001)";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "xmrig-proxy.service"
      ];
      environment = {
        HOME = "/var/lib/ktunnel-wiit";
        KUBECONFIG = cfg.kubeconfig;
      };
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStartPre = "-${pkgs.kubectl}/bin/kubectl --kubeconfig ${cfg.kubeconfig} create namespace ${cfg.namespace}";
        ExecStart = "${pkgs.ktunnel}/bin/ktunnel expose ${cfg.serviceName} ${toString cfg.localPort} --namespace ${cfg.namespace} --server-image ${cfg.image} --reuse";
        Restart = "on-failure";
        RestartSec = "30s";
        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/ktunnel-wiit" ];
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
