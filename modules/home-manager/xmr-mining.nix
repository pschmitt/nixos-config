{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
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

  clusterOptions =
    { name, ... }:
    {
      options = {
        kubeContext = mkOption {
          type = types.str;
          description = "Full kubectl context name for this cluster.";
        };
        kubeconfig = mkOption {
          type = types.str;
          description = "Path to the kubeconfig file containing the cluster context.";
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
          default = "/var/lib/ktunnel-wiit/kubeconfig";
          description = "Path to write the synced kubeconfig on targetHost.";
        };
        remoteProxyPasswordPath = mkOption {
          type = types.str;
          default = "/run/secrets/xmrig-proxy/password";
          description = "Path to the xmrig-proxy password secret on targetHost.";
        };
        namespace = mkOption {
          type = types.str;
          default = "xmr";
          description = "Kubernetes namespace to deploy miners into.";
        };
      };
    };

  syncServiceName = name: "xmrig-sync-${name}";

  makeDaemonsetYaml =
    name: cluster:
    pkgs.writeText "xmrig-daemonset-${name}.yaml" ''
      apiVersion: apps/v1
      kind: DaemonSet
      metadata:
        name: xmrig
        namespace: ${cluster.namespace}
        labels:
          app: xmrig
      spec:
        selector:
          matchLabels:
            app: xmrig
        template:
          metadata:
            labels:
              app: xmrig
          spec:
            nodeSelector:
              node-role.kubernetes.io/compute: "true"
            containers:
              - name: xmrig
                image: artifactory.prod.capp.wiit-cloud.io/docker-ghcr-io-remote/metal3d/xmrig:latest
                command:
                  - /bin/bash
                  - -c
                  - |
                    node_name="''${NODE_NAME:-''${HOSTNAME:-$(hostname)}}"
                    exec xmrig -o "''${POOL_URL}" --nicehash -p "''${POOL_PASS}" --rig-id "''${node_name}" --donate-level 1
                securityContext:
                  privileged: true
                env:
                  - name: NODE_NAME
                    valueFrom:
                      fieldRef:
                        fieldPath: spec.nodeName
                  - name: POOL_URL
                    value: xmrig-proxy.${cluster.namespace}.svc.cluster.local:3333
                  - name: POOL_PASS
                    valueFrom:
                      secretKeyRef:
                        name: xmrig-proxy-password
                        key: password
    '';

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

      TMP_KUBECONFIG=$(mktemp)
      trap 'rm -f "$TMP_KUBECONFIG"' EXIT

      ${pkgs.kubectl}/bin/kubectl config view \
        --minify --context '${cluster.kubeContext}' --raw \
        > "$TMP_KUBECONFIG"

      REMOTE_TMP=$(ssh '${cluster.targetHost}' mktemp)
      scp "$TMP_KUBECONFIG" "${cluster.targetHost}:$REMOTE_TMP"
      ssh '${cluster.targetHost}' \
        sudo install --verbose -D \
          --mode=0640 --owner=ktunnel --group=ktunnel \
          "$REMOTE_TMP" '${cluster.remoteKubeconfig}'
      ssh '${cluster.targetHost}' rm -f "$REMOTE_TMP"

      ${pkgs.kubectl}/bin/kubectl \
        --context '${cluster.kubeContext}' \
        create namespace '${cluster.namespace}' \
        --dry-run=client -o yaml | \
        ${pkgs.kubectl}/bin/kubectl --context '${cluster.kubeContext}' apply -f -

      PROXY_PASS=$(ssh '${cluster.targetHost}' sudo cat '${cluster.remoteProxyPasswordPath}')
      ${pkgs.kubectl}/bin/kubectl \
        --context '${cluster.kubeContext}' \
        create secret generic xmrig-proxy-password \
        --namespace '${cluster.namespace}' \
        --from-literal=password="$PROXY_PASS" \
        --dry-run=client -o yaml | \
        ${pkgs.kubectl}/bin/kubectl --context '${cluster.kubeContext}' apply -f -

      ${pkgs.kubectl}/bin/kubectl get secret artifactory \
        --context '${cluster.kubeContext}' \
        --namespace kube-system \
        -o json | \
        ${pkgs.python3}/bin/python3 -c "
      import json, sys
      d = json.load(sys.stdin)
      print(json.dumps({
        'apiVersion': 'v1',
        'kind': 'Secret',
        'metadata': {'name': 'artifactory', 'namespace': '${cluster.namespace}'},
        'type': d['type'],
        'data': d['data'],
      }))" | \
        ${pkgs.kubectl}/bin/kubectl --context '${cluster.kubeContext}' apply -f -

      ${pkgs.kubectl}/bin/kubectl \
        --context '${cluster.kubeContext}' \
        patch serviceaccount default \
        --namespace '${cluster.namespace}' \
        -p '{"imagePullSecrets": [{"name": "artifactory"}]}'

      ${pkgs.kubectl}/bin/kubectl \
        --context '${cluster.kubeContext}' \
        apply -f ${daemonset}

      ssh '${cluster.targetHost}' sudo systemctl restart '${cluster.ktunnelService}' || true
    '';

  clusterNames = builtins.attrNames cfg.clusters;
  defaultCtx = if builtins.length clusterNames == 1 then builtins.head clusterNames else "";

  mkCtxCase = name: cluster: ''
    ${escapeShellArg name})
      kube_context=${escapeShellArg cluster.kubeContext}
      kube_config=${escapeShellArg cluster.kubeconfig}
      target_host=${escapeShellArg cluster.targetHost}
      ktunnel_svc=${escapeShellArg cluster.ktunnelService}
      namespace=${escapeShellArg cluster.namespace}
      sync_svc=${escapeShellArg (syncServiceName name)}
      ;;'';

  minerctl = pkgs.writeShellScriptBin "minerctl" ''
    set -eu

    SSH_OPTS="-F /dev/null -o UserKnownHostsFile=$HOME/.ssh/known_hosts -o StrictHostKeyChecking=yes"
    ssh() { ${pkgs.openssh}/bin/ssh $SSH_OPTS "$@"; }
    kubectl() { ${pkgs.kubectl}/bin/kubectl "$@"; }
    kube() { KUBECTL_COMMAND=${pkgs.kubectl}/bin/kubectl ${pkgs.kubecolor}/bin/kubecolor "$@"; }

    usage() {
      cat >&2 <<EOF
    Usage: $(basename "$0") [--context CTX] ACTION

    Actions:
      start   sync kubeconfig, bootstrap secrets, deploy miners
      stop    delete namespace and stop ktunnel
      status  brief cluster overview (alias: show)
      logs    tail pod and ktunnel logs

    Options:
      -c, --context CTX   cluster context  (${lib.concatStringsSep "|" clusterNames})
      -n, --namespace NS  override kubernetes namespace
      -h, --help          show this help
    EOF
    }

    ctx=${escapeShellArg defaultCtx}
    cmd=
    ns_override=

    while [[ -n "''${1:-}" ]]
    do
      case "$1" in
        -c|--context)
          ctx="$2"
          shift 2
          ;;
        -n|--namespace)
          ns_override="$2"
          shift 2
          ;;
        start|stop|status|show|logs)
          cmd="$1"
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done

    if [[ -z "$ctx" || -z "$cmd" ]]
    then
      usage
      exit 2
    fi

    case "$ctx" in
      ${concatMapStringsSep "\n      " (name: mkCtxCase name cfg.clusters.${name}) clusterNames}
      *)
        printf 'Unknown context: %s\n' "$ctx" >&2
        usage
        exit 2
        ;;
    esac

    if [[ -n "$ns_override" ]]
    then
      namespace="$ns_override"
    fi

    case "$cmd" in
      start)
        echo "[$ctx] Syncing kubeconfig, bootstrapping secrets, deploying miners..."
        systemctl --user reset-failed "$sync_svc.service" 2>/dev/null || true
        systemctl --user start "$sync_svc.service"
        echo "[$ctx] Done."
        ;;

      stop)
        echo "[$ctx] Deleting namespace $namespace (removes miners, ktunnel pod, secrets)..."
        kubectl \
          --kubeconfig "$kube_config" \
          --context "$kube_context" \
          delete namespace "$namespace" --ignore-not-found
        echo "[$ctx] Stopping ktunnel client on $target_host..."
        ssh "$target_host" sudo systemctl stop "$ktunnel_svc" || true
        echo "[$ctx] Stopped."
        ;;

      status|show)
        _ktunnel_state=$(
          ssh "$target_host" "systemctl is-active '$ktunnel_svc'" 2>/dev/null \
            || echo "unknown"
        )
        case "$_ktunnel_state" in
          active)
            printf 'ktunnel (%s):  \e[32m%s\e[0m\n' "$target_host" "$_ktunnel_state"
            ;;
          failed)
            printf 'ktunnel (%s):  \e[1;31m%s\e[0m\n' "$target_host" "$_ktunnel_state"
            ;;
          *)
            printf 'ktunnel (%s):  \e[33m%s\e[0m\n' "$target_host" "$_ktunnel_state"
            ;;
        esac
        if [[ "$_ktunnel_state" != "active" ]]
        then
          ssh "$target_host" \
            "SYSTEMD_COLORS=1 systemctl status '$ktunnel_svc' --no-pager -l" \
            2>&1 || true
        fi

        echo ""
        kubectl \
          --kubeconfig "$kube_config" \
          --context "$kube_context" \
          get pods -n "$namespace" -o wide 2>/dev/null \
          | awk '{print $1, $2, $3, $4, $5, $7}' \
          | ${pkgs.util-linux}/bin/column -t \
          | sed \
              -e 's/\bRunning\b/\x1b[32m&\x1b[0m/g' \
              -e 's/\bPending\b/\x1b[33m&\x1b[0m/g' \
              -e 's/\bError\b\|\bCrashLoopBackOff\b\|\bOOMKilled\b/\x1b[1;31m&\x1b[0m/g' \
          || echo "(no pods)"

        echo ""
        _nodes_json=$(
          kubectl \
            --kubeconfig "$kube_config" \
            --context "$kube_context" \
            get pods -l app=xmrig -n "$namespace" -o json 2>/dev/null \
          | ${pkgs.jq}/bin/jq '[.items[].spec.nodeName] | unique' \
          || echo '[]'
        )
        _workers_json=$(
          ssh "$target_host" \
            "curl -sf http://127.0.0.1:9674/1/workers 2>/dev/null" 2>/dev/null \
          || true
        )
        if [[ -z "$_workers_json" ]]
        then
          echo "(proxy unavailable)"
        else
          ${pkgs.jq}/bin/jq -r --argjson nodes "$_nodes_json" '
            def nth($a; $i): if ($a | type) == "array" then ($a[$i] // 0) else 0 end;
            def rates($w): if ($w[8]? | type) == "array" then $w[8] else ($w[8:] // []) end;
            def fmt($n): ($n * 100 | round) / 100 | tostring;
            [.workers[] | select(.[0] as $n | $nodes | index($n) != null)] as $fw
            | [
                ["NAME", "1M", "10M", "1H"],
                ($fw[] | [.[0],
                  (rates(.) | fmt(nth(.; 0))),
                  (rates(.) | fmt(nth(.; 1))),
                  (rates(.) | fmt(nth(.; 2)))]),
                ["TOTAL",
                  fmt([$fw[] | rates(.) | nth(.; 0)] | add // 0),
                  fmt([$fw[] | rates(.) | nth(.; 1)] | add // 0),
                  fmt([$fw[] | rates(.) | nth(.; 2)] | add // 0)]
              ][] | @tsv
          ' <<< "$_workers_json" \
            | ${pkgs.util-linux}/bin/column -t \
            | sed -e '1s/.*/\x1b[1m&\x1b[0m/' -e 's/^TOTAL.*/\x1b[1;36m&\x1b[0m/'
        fi
        ;;

      logs)
        echo "=== xmrig pod logs ($namespace) ==="
        kubectl \
          --kubeconfig "$kube_config" \
          --context "$kube_context" \
          logs -l app=xmrig -n "$namespace" --tail=50 --prefix 2>/dev/null \
          || echo "(no logs)"

        echo ""
        echo "=== ktunnel server pod logs ($namespace) ==="
        _pod_json=$(
          kubectl \
            --kubeconfig "$kube_config" \
            --context "$kube_context" \
            get pods -n "$namespace" -o json 2>/dev/null \
            || echo '{"items":[]}'
        )
        _ktunnel_pod=$(
          ${pkgs.jq}/bin/jq -r \
            'first(.items[] | select(.metadata.name | test("(?i)ktunnel")) | .metadata.name) // ""' \
            <<< "$_pod_json"
        )
        if [[ -n "$_ktunnel_pod" ]]
        then
          kubectl \
            --kubeconfig "$kube_config" \
            --context "$kube_context" \
            logs "$_ktunnel_pod" -n "$namespace" --tail=50 2>/dev/null \
            || echo "(no logs)"
        else
          echo "(ktunnel pod not found)"
        fi

        echo ""
        echo "=== ktunnel journal ($target_host) ==="
        ssh "$target_host" \
          "SYSTEMD_COLORS=1 journalctl -u '$ktunnel_svc' -n 50 --no-pager" \
          2>&1 || echo "(unavailable)"
        ;;
    esac

    # vim: set ft=sh et ts=2 sw=2 :
  '';

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

    clusters = mkOption {
      type = types.attrsOf (types.submodule clusterOptions);
      default = { };
      description = "Mining clusters to manage, keyed by short name.";
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services = mapAttrs' (
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
            "KUBECONFIG=${cluster.kubeconfig}"
          ];
          ExecStart = makeSyncScript name cluster;
        };
      }
    ) cfg.clusters;

    systemd.user.timers = mapAttrs' (
      name: cluster:
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
    ) cfg.clusters;

    home.packages = [ minerctl ] ++ perClusterWrappers;
  };
}
