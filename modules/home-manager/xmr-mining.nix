{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    escapeShellArg
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;
  cfg = config.xmr.mining;
  yamlFormat = pkgs.formats.yaml { };

  # Applied to every resource minerctl creates (namespace, secrets,
  # DaemonSet) so they stay findable/deletable by selector even if we
  # later rename them.
  managedByLabelKey = "app.kubernetes.io/managed-by";
  managedByLabelValue = "minerctl";
  managedByLabelSelector = "${managedByLabelKey}=${managedByLabelValue}";

  clusterOptions =
    { name, ... }:
    {
      options = {
        kubeContext = mkOption {
          type = types.str;
          default = "";
          description = "Full kubectl context name. Leave empty and set kubeContextFile to read from a secret at runtime.";
        };
        kubeContextFile = mkOption {
          type = types.str;
          default = "";
          description = "Path to a file containing the kubectl context name (e.g., a sops-nix secret path).";
        };
        kubeconfig = mkOption {
          type = types.str;
          default = "";
          description = "Path to the kubeconfig file. Leave empty and set kubeconfigFile to read from a secret at runtime.";
        };
        kubeconfigFile = mkOption {
          type = types.str;
          default = "";
          description = "Path to a file containing the kubeconfig path (e.g., a sops-nix secret).";
        };
        targetHost = mkOption {
          type = types.str;
          description = "SSH hostname of the machine running the ktunnel client.";
        };
        ktunnelService = mkOption {
          type = types.str;
          description = "Systemd service name for the ktunnel client on targetHost.";
        };
        remoteKubeconfig = mkOption {
          type = types.str;
          default = "/var/lib/ktunnel/kubeconfig";
          description = "Path to write the synced kubeconfig on targetHost.";
        };
        remoteProxyPasswordPath = mkOption {
          type = types.str;
          default = "/run/secrets/xmrig-proxy/password";
          description = "Path to the xmrig-proxy password secret on targetHost.";
        };
        namespace = mkOption {
          type = types.str;
          default = "local-x";
          description = "Kubernetes namespace to deploy miners into.";
        };
        deleteNamespaceOnStop = mkOption {
          type = types.bool;
          default = true;
          description = "Whether `minerctl stop`/`restart` deletes the namespace. When false, stop only removes the xmrig DaemonSet, leaving the namespace (and its secrets) in place; overridable per-invocation with `minerctl --keep-namespace stop`.";
        };
      };
    };

  syncServiceName = name: "xmrig-sync-kubeconfig-${name}";

  kubeContextArg =
    cluster:
    if cluster.kubeContextFile != "" then
      ''"$(cat ${escapeShellArg cluster.kubeContextFile})"''
    else
      escapeShellArg cluster.kubeContext;

  kubeconfigArg =
    cluster:
    if cluster.kubeconfigFile != "" then
      ''"$(cat ${escapeShellArg cluster.kubeconfigFile})"''
    else
      escapeShellArg cluster.kubeconfig;

  makeDaemonsetYaml =
    name: cluster:
    yamlFormat.generate "xmrig-daemonset-${name}.yaml" {
      apiVersion = "apps/v1";
      kind = "DaemonSet";
      metadata = {
        name = "xmrig";
        inherit (cluster) namespace;
        labels = {
          app = "xmrig";
          ${managedByLabelKey} = managedByLabelValue;
        };
      };
      spec = {
        selector.matchLabels.app = "xmrig";
        template = {
          metadata.labels = {
            app = "xmrig";
            ${managedByLabelKey} = managedByLabelValue;
          };
          spec = {
            affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key = "node-role.kubernetes.io/compute";
                    operator = "Exists";
                  }
                ];
              }
            ];
            containers = [
              {
                name = "xmrig";
                image = "artifactory.prod.capp.wiit-cloud.io/docker-ghcr-io-remote/metal3d/xmrig:latest";
                command = [
                  "/bin/bash"
                  "-c"
                  ''
                    node_name="''${NODE_NAME:-''${HOSTNAME:-$(hostname)}}"
                    exec xmrig -o "''${POOL_URL}" --nicehash -p "''${POOL_PASS}" --rig-id "''${node_name}" --donate-level 1
                  ''
                ];
                securityContext.privileged = true;
                env = [
                  {
                    name = "NODE_NAME";
                    valueFrom.fieldRef.fieldPath = "spec.nodeName";
                  }
                  {
                    name = "POOL_URL";
                    value = "xmrig-proxy.${cluster.namespace}.svc.cluster.local:3333";
                  }
                  {
                    name = "POOL_PASS";
                    valueFrom.secretKeyRef = {
                      name = "xmrig-proxy-password";
                      key = "password";
                    };
                  }
                ];
              }
            ];
          };
        };
      };
    };

  makeSyncScript =
    name: cluster:
    let
      daemonset = makeDaemonsetYaml name cluster;
    in
    pkgs.writeShellScript "xmrig-sync-${name}.sh" ''
      set -eu

      # Fedora 44: nixpkgs openssh doesn't recognise ML-KEM from system crypto-policies
      SSH_OPTS="-F /dev/null -o UserKnownHostsFile=$HOME/.ssh/known_hosts -o StrictHostKeyChecking=yes"
      ssh() { ${pkgs.openssh}/bin/ssh $SSH_OPTS "$@"; }
      scp() { ${pkgs.openssh}/bin/scp $SSH_OPTS "$@"; }

      KUBE_CONTEXT=${kubeContextArg cluster}
      export KUBECONFIG=${kubeconfigArg cluster}

      TMP_KUBECONFIG=$(mktemp)
      trap 'rm -f "$TMP_KUBECONFIG"' EXIT

      ${pkgs.kubectl}/bin/kubectl config view \
        --minify --context "$KUBE_CONTEXT" --raw \
        > "$TMP_KUBECONFIG"

      REMOTE_TMP=$(ssh '${cluster.targetHost}' mktemp)
      scp "$TMP_KUBECONFIG" "${cluster.targetHost}:$REMOTE_TMP"
      ssh '${cluster.targetHost}' \
        sudo install --verbose -D \
          --mode=0640 --owner=ktunnel --group=ktunnel \
          "$REMOTE_TMP" '${cluster.remoteKubeconfig}'
      ssh '${cluster.targetHost}' rm -f "$REMOTE_TMP"

      ${pkgs.kubectl}/bin/kubectl \
        --context "$KUBE_CONTEXT" \
        create namespace '${cluster.namespace}' \
        --dry-run=client -o yaml | \
        ${pkgs.kubectl}/bin/kubectl --context "$KUBE_CONTEXT" apply -f -
      ${pkgs.kubectl}/bin/kubectl \
        --context "$KUBE_CONTEXT" \
        label namespace '${cluster.namespace}' ${managedByLabelSelector} --overwrite

      PROXY_PASS=$(ssh '${cluster.targetHost}' sudo cat '${cluster.remoteProxyPasswordPath}')
      ${pkgs.kubectl}/bin/kubectl \
        --context "$KUBE_CONTEXT" \
        create secret generic xmrig-proxy-password \
        --namespace '${cluster.namespace}' \
        --from-literal=password="$PROXY_PASS" \
        --dry-run=client -o yaml | \
        ${pkgs.kubectl}/bin/kubectl --context "$KUBE_CONTEXT" apply -f -
      ${pkgs.kubectl}/bin/kubectl \
        --context "$KUBE_CONTEXT" \
        label secret xmrig-proxy-password \
        --namespace '${cluster.namespace}' ${managedByLabelSelector} --overwrite

      ${pkgs.kubectl}/bin/kubectl get secret artifactory \
        --context "$KUBE_CONTEXT" \
        --namespace kube-system \
        -o json | \
        ${pkgs.python3}/bin/python3 -c "
      import json, sys
      d = json.load(sys.stdin)
      print(json.dumps({
        'apiVersion': 'v1',
        'kind': 'Secret',
        'metadata': {
          'name': 'artifactory',
          'namespace': '${cluster.namespace}',
          'labels': {'${managedByLabelKey}': '${managedByLabelValue}'},
        },
        'type': d['type'],
        'data': d['data'],
      }))" | \
        ${pkgs.kubectl}/bin/kubectl --context "$KUBE_CONTEXT" apply -f -

      ${pkgs.kubectl}/bin/kubectl \
        --context "$KUBE_CONTEXT" \
        patch serviceaccount default \
        --namespace '${cluster.namespace}' \
        -p '{"imagePullSecrets": [{"name": "artifactory"}]}'

      ${pkgs.kubectl}/bin/kubectl \
        --context "$KUBE_CONTEXT" \
        apply -f ${daemonset}

      ssh '${cluster.targetHost}' sudo systemctl restart '${cluster.ktunnelService}' || true
    '';

  clusterNames = builtins.attrNames cfg.clusters;

  clusterColorPalette = [
    "\\x1b[36m"
    "\\x1b[35m"
    "\\x1b[94m"
    "\\x1b[33m"
  ];

  clusterColor =
    i: builtins.elemAt clusterColorPalette (lib.mod i (builtins.length clusterColorPalette));

  clusterColorMap = lib.listToAttrs (
    lib.imap0 (i: name: nameValuePair name (clusterColor i)) clusterNames
  );

  # Cluster data consumed by minerctl at runtime — resolves the *File secrets,
  # contexts and colours — instead of baking a case statement into the script.
  clustersJson = (pkgs.formats.json { }).generate "minerctl-clusters.json" (
    lib.mapAttrs (name: cluster: {
      kube_context = cluster.kubeContext;
      kube_context_file = cluster.kubeContextFile;
      kube_config = cluster.kubeconfig;
      kube_config_file = cluster.kubeconfigFile;
      target_host = cluster.targetHost;
      ktunnel_svc = cluster.ktunnelService;
      inherit (cluster) namespace;
      delete_namespace_on_stop = cluster.deleteNamespaceOnStop;
      managed_by_label = managedByLabelSelector;
      sync_svc = syncServiceName name;
      color = clusterColorMap.${name};
    }) cfg.clusters
  );

  minerctl = pkgs.writeShellApplication {
    name = "minerctl";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      jq
      kubectl
      openssh
      util-linux
    ];
    text = ''
      CLUSTERS_JSON=${clustersJson}
      ${builtins.readFile ./scripts/minerctl.sh}
    '';
  };

  perClusterWrappers = mapAttrsToList (
    name: _:
    pkgs.writeShellScriptBin "minerctl-${name}" ''
      exec ${minerctl}/bin/minerctl --context ${escapeShellArg name} "$@"
    ''
  ) cfg.clusters;
in
{
  options.xmr.mining = {
    enable = mkEnableOption "xmrig mining cluster management";

    enableSync = mkOption {
      type = types.bool;
      default = false;
      description = "Enable kubeconfig sync services and timers. Only needed on the host that holds the kubeconfig secrets (fnuc).";
    };

    clusters = mkOption {
      type = types.attrsOf (types.submodule clusterOptions);
      default = { };
      description = "Mining clusters to manage, keyed by short name.";
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services = mkIf cfg.enableSync (
      mapAttrs' (
        name: cluster:
        nameValuePair (syncServiceName name) {
          Unit = {
            Description = "Sync kubeconfig and bootstrap xmrig mining on ${name}";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "LANG=en_US.UTF-8"
              "LC_ALL=en_US.UTF-8"
            ]
            ++ (if cluster.kubeconfig != "" then [ "KUBECONFIG=${cluster.kubeconfig}" ] else [ ]);
            ExecStart = makeSyncScript name cluster;
          };
        }
      ) cfg.clusters
    );

    systemd.user.timers = mkIf cfg.enableSync (
      mapAttrs' (
        name: _:
        nameValuePair (syncServiceName name) {
          Unit.Description = "Periodically sync kubeconfig for xmrig mining on ${name}";
          Timer = {
            OnBootSec = "5min";
            OnUnitActiveSec = "1h";
            RandomizedDelaySec = "5min";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        }
      ) cfg.clusters
    );

    home.packages = [ minerctl ] ++ perClusterWrappers;
  };
}
