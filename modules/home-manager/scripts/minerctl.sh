# minerctl — manage xmrig mining DaemonSets across kubernetes clusters.
#
# Wrapped by writeShellApplication: the shebang, `set -euo pipefail` and PATH
# (runtimeInputs) are injected by Nix, and the `CLUSTERS_JSON` variable (path to
# the generated cluster-data file) is prepended by the wrapper. All cluster
# specifics are read from that JSON at runtime via jq, so this file is static.
#
# The upstream script ran with `set -eu` (no pipefail); keep that here — several
# `jq | column | sed` pipelines rely on the last stage's exit status.
set +o pipefail

# ssh with the repo's hardened defaults (openssh from runtimeInputs).
ssh() {
  command ssh \
    -F /dev/null \
    -o "UserKnownHostsFile=$HOME/.ssh/known_hosts" \
    -o StrictHostKeyChecking=yes \
    "$@"
}

red() {
  printf '\e[1;31m%s\e[0m\n' "$*"
}

# Cluster names and the "a|b|c" form for help text.
mapfile -t all_ctx_names < <(jq -r 'keys[]' "$CLUSTERS_JSON")
ctx_list=$(jq -r 'keys | join("|")' "$CLUSTERS_JSON")

# { "<cluster>": "<color-escape>" } map, used to colourise cluster/node names.
color_map=$(jq 'map_values(.color)' "$CLUSTERS_JSON")

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") [--context CTX|-A] ACTION

Actions:
  start   sync kubeconfig, bootstrap secrets, deploy miners
  stop    stop miners and ktunnel; deletes the namespace unless kept
            (see --keep-namespace and the deleteNamespaceOnStop option)
  restart stop, then start
  status  brief cluster overview (alias: show)
  logs    tail pod and ktunnel logs
            logs                 xmrig + ktunnel logs (default)
            logs tun|ktunnel     only ktunnel logs
            logs x|xmrig         only xmrig logs
            logs HOSTNAME        only the miner pod on that node

Options:
  -c, --context CTX     cluster context  (${ctx_list})
  -a, -A, --all         run action across all clusters
  -j, --json            output status as JSON
  -f, --follow          follow log output (logs command only)
  -n, --namespace NS    override kubernetes namespace
  -k, --keep-namespace  on stop/restart, keep the namespace (delete the
                         xmrig DaemonSet and its secrets instead);
                         overrides deleteNamespaceOnStop
  -h, --help            show this help
EOF
}

# Resolve the selected context into the kube_*/target_host/... globals.
# Returns non-zero if $ctx is not a known cluster.
resolve_context() {
  local entry kcf kgf
  entry=$(jq -e -c --arg c "$ctx" '.[$c] // empty' "$CLUSTERS_JSON") || return 1

  kcf=$(jq -r '.kube_context_file' <<< "$entry")
  if [[ -n "$kcf" ]]
  then
    kube_context=$(cat "$kcf")
  else
    kube_context=$(jq -r '.kube_context' <<< "$entry")
  fi

  kgf=$(jq -r '.kube_config_file' <<< "$entry")
  if [[ -n "$kgf" ]]
  then
    kube_config=$(cat "$kgf")
  else
    kube_config=$(jq -r '.kube_config' <<< "$entry")
  fi

  target_host=$(jq -r '.target_host' <<< "$entry")
  ktunnel_svc=$(jq -r '.ktunnel_svc' <<< "$entry")
  namespace=$(jq -r '.namespace' <<< "$entry")
  delete_ns_on_stop=$(jq -r '.delete_namespace_on_stop' <<< "$entry")
  managed_by_label=$(jq -r '.managed_by_label' <<< "$entry")
  sync_svc=$(jq -r '.sync_svc' <<< "$entry")
  ctx_color=$(jq -r '.color' <<< "$entry")
}

ctx=$(jq -r 'if length == 1 then (keys | .[0]) else "" end' "$CLUSTERS_JSON")
cmd=
ns_override=
all_clusters=
json_output=
follow=
log_target=
keep_ns=

while [[ -n "${1:-}" ]]
do
  case "$1" in
    -c|--context)
      ctx="$2"
      shift 2
      ;;
    -a|-A|--all)
      all_clusters=1
      shift
      ;;
    -j|--json)
      json_output=1
      shift
      ;;
    -f|--follow)
      follow=1
      shift
      ;;
    -n|--namespace)
      ns_override="$2"
      shift 2
      ;;
    -k|--keep-namespace)
      keep_ns=1
      shift
      ;;
    start|stop|restart|status|show|logs)
      cmd="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # First bare word after an action is a log target (subcommand/hostname).
      if [[ -z "$cmd" || -n "$log_target" ]]
      then
        usage
        exit 2
      fi
      log_target="$1"
      shift
      ;;
  esac
done

if [[ -z "$cmd" ]]
then
  usage
  exit 2
fi

if [[ -z "$ctx" && -z "$all_clusters" ]]
then
  case "$cmd" in
    start|stop|restart|status|show|logs)
      all_clusters=1
      ;;
    *)
      usage
      exit 2
      ;;
  esac
fi

if [[ -n "$all_clusters" ]]
then
  case "$cmd" in
    start|stop|restart)
      for _ctx in "${all_ctx_names[@]}"
      do
        _extra=()
        if [[ -n "$ns_override" ]]
        then
          _extra+=(--namespace "$ns_override")
        fi
        if [[ -n "$keep_ns" ]]
        then
          _extra+=(--keep-namespace)
        fi
        "$0" --context "$_ctx" "$cmd" "${_extra[@]}"
      done
      exit 0
      ;;
    logs)
      _pids=()
      for _ctx in "${all_ctx_names[@]}"
      do
        _extra=()
        if [[ -n "$ns_override" ]]
        then
          _extra+=(--namespace "$ns_override")
        fi
        if [[ -n "$follow" ]]
        then
          _extra+=(--follow)
        fi
        if [[ -n "$log_target" ]]
        then
          _extra+=("$log_target")
        fi
        "$0" --context "$_ctx" logs "${_extra[@]}" &
        _pids+=("$!")
      done
      wait "${_pids[@]}"
      exit 0
      ;;
    status|show)
      _all_json=()
      for _ctx in "${all_ctx_names[@]}"
      do
        _extra=()
        if [[ -n "$ns_override" ]]
        then
          _extra+=(--namespace "$ns_override")
        fi
        _cj=$(
          "$0" --context "$_ctx" --json status "${_extra[@]}" 2>/dev/null \
          || printf '{"cluster":"%s","kube_context":"","target_host":"","ktunnel_state":"unknown","nodes":[],"total":{"r1m":0,"r10m":0,"r1h":0}}' "$_ctx"
        )
        _all_json+=("$_cj")
      done

      if [[ -n "$json_output" ]]
      then
        printf '%s\n' "${_all_json[@]}" | jq -s '.'
        exit 0
      fi

      _combined_json=$(printf '%s\n' "${_all_json[@]}" | jq -s '.')

      # Per-cluster colour sed args for the KTUNNEL table.
      _cluster_color_sed_args=()
      while IFS= read -r _sed_expr
      do
        _cluster_color_sed_args+=("-e" "$_sed_expr")
      done < <(jq -r 'to_entries[] | "s/" + .key + "/" + .value.color + "&\\x1b[0m/g"' "$CLUSTERS_JSON")

      printf '\e[1mKTUNNEL\e[0m\n'
      jq -r '
        ["CLUSTER", "CONTEXT", "HOST", "STATE"],
        (.[] | [.cluster, .kube_context, .target_host, .ktunnel_state])
        | @tsv
      ' <<< "$_combined_json" \
        | column -t -s $'\t' \
        | sed \
            -e '1s/.*/\x1b[1m&\x1b[0m/' \
            "${_cluster_color_sed_args[@]}" \
            -e 's/\bactive\b/\x1b[32m&\x1b[0m/g' \
            -e 's/\bfailed\b/\x1b[1;31m&\x1b[0m/g' \
            -e 's/\bunknown\b/\x1b[33m&\x1b[0m/g'

      # Build per-node color sed args from cluster membership
      _node_color_sed_args=()
      while IFS= read -r _sed_expr
      do
        _node_color_sed_args+=("-e" "$_sed_expr")
      done < <(jq -r \
        --argjson colors "$color_map" '
        .[] | .cluster as $c | .nodes[] | .node |
        "s/" + . + "/" + $colors[$c] + "&\\x1b[0m/g"
      ' <<< "$_combined_json" 2>/dev/null)

      echo ""
      printf '\e[1mMINERS\e[0m\n'
      jq -r '
        def fmt($n): ($n * 100 | round) / 100 | tostring;
        [.[] | .cluster as $c | .nodes[] | . + {cluster: $c}] as $rows
        | if ($rows | length) == 0
          then "(no miners)"
          else
            ([$rows[] | .restarts] | any(. > 0)) as $has_restarts
            | [
                (["NODE", "POD NAME", "STATUS"] +
                 (if $has_restarts then ["RESTARTS"] else [] end) +
                 ["AGE", "1M(MH/s)", "10M(MH/s)", "1H(MH/s)"]),
                ($rows[] |
                 [.node, .pod_name, .status] +
                 (if $has_restarts then [.restarts | tostring] else [] end) +
                 [.age, fmt(.r1m), fmt(.r10m), fmt(.r1h)]),
                (["TOTAL"] +
                 (if $has_restarts then ["", "", "", ""] else ["", "", ""] end) +
                 [fmt([$rows[] | .r1m] | add // 0),
                  fmt([$rows[] | .r10m] | add // 0),
                  fmt([$rows[] | .r1h] | add // 0)])
              ][] | @tsv
          end
      ' <<< "$_combined_json" \
        | column -t -s $'\t' \
        | sed \
            -e '1s/.*/\x1b[1m&\x1b[0m/' \
            "${_node_color_sed_args[@]}" \
            -e 's/\bRunning\b/\x1b[32m&\x1b[0m/g' \
            -e 's/\bPending\b/\x1b[33m&\x1b[0m/g' \
            -e 's/\bError\b\|\bCrashLoopBackOff\b\|\bOOMKilled\b/\x1b[1;31m&\x1b[0m/g' \
            -e 's/^TOTAL.*/\x1b[1;36m&\x1b[0m/'
      exit 0
      ;;
    *)
      printf 'Action "%s" does not support --all\n' "$cmd" >&2
      usage
      exit 2
      ;;
  esac
fi

if ! resolve_context
then
  printf 'Unknown context: %s\n' "$ctx" >&2
  usage
  exit 2
fi

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
    _delete_ns=1
    if [[ -n "$keep_ns" || "$delete_ns_on_stop" != "true" ]]
    then
      _delete_ns=
    fi

    if [[ -n "$_delete_ns" ]]
    then
      echo "[$ctx] Deleting namespace $namespace (removes miners, ktunnel pod, secrets)..."
      kubectl \
        --kubeconfig "$kube_config" \
        --context "$kube_context" \
        delete namespace "$namespace" --ignore-not-found
    else
      echo "[$ctx] Keeping namespace $namespace; deleting minerctl-managed resources ($managed_by_label)..."
      kubectl \
        --kubeconfig "$kube_config" \
        --context "$kube_context" \
        delete daemonset,secret -n "$namespace" -l "$managed_by_label" --ignore-not-found
    fi
    echo "[$ctx] Stopping ktunnel client on $target_host..."
    # shellcheck disable=SC2029  # $ktunnel_svc is expanded locally on purpose
    ssh "$target_host" sudo systemctl stop "$ktunnel_svc" || true
    echo "[$ctx] Stopped."
    ;;

  restart)
    _extra=()
    if [[ -n "$ns_override" ]]
    then
      _extra+=(--namespace "$ns_override")
    fi
    _stop_extra=("${_extra[@]}")
    if [[ -n "$keep_ns" ]]
    then
      _stop_extra+=(--keep-namespace)
    fi
    "$0" --context "$ctx" stop "${_stop_extra[@]}"
    "$0" --context "$ctx" start "${_extra[@]}"
    ;;

  status|show)
    _ktunnel_state=$(
      # shellcheck disable=SC2029  # $ktunnel_svc is expanded locally on purpose
      ssh "$target_host" "systemctl is-active '$ktunnel_svc'; true" 2>/dev/null \
        || echo "unknown"
    )
    _pods_json=$(
      kubectl \
        --kubeconfig "$kube_config" \
        --context "$kube_context" \
        get pods -l app=xmrig -n "$namespace" -o json 2>/dev/null \
      || echo '{"items":[]}'
    )
    _workers_json=$(
      ssh "$target_host" \
        "curl -sf http://127.0.0.1:9674/1/workers 2>/dev/null" 2>/dev/null \
      || echo '{"workers":[]}'
    )

    if [[ -n "$json_output" ]]
    then
      jq -n \
        --arg cluster "$ctx" \
        --arg kube_context "$kube_context" \
        --arg target_host "$target_host" \
        --arg ktunnel_state "$_ktunnel_state" \
        --argjson pods "$_pods_json" \
        --argjson workers "$_workers_json" '
        ($workers.workers | map({key: .[0], value: .}) | from_entries) as $wmap
        | ($pods.items | map({
            pod_name: .metadata.name,
            node: (.spec.nodeName // "<none>"),
            status: (.status.phase // "Unknown"),
            restarts: (.status.containerStatuses[0]?.restartCount // 0),
            age: (
              (now - (.metadata.creationTimestamp | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) as $s
              | if $s < 60 then ($s | round | tostring) + "s"
                elif $s < 3600 then ($s / 60 | floor | tostring) + "m"
                elif $s < 86400 then ($s / 3600 | floor | tostring) + "h"
                else ($s / 86400 | floor | tostring) + "d"
                end
            ),
            r1m: ($wmap[.spec.nodeName][8] // 0),
            r10m: ($wmap[.spec.nodeName][9] // 0),
            r1h: ($wmap[.spec.nodeName][10] // 0)
          })) as $nodes
        | {
            cluster: $cluster,
            kube_context: $kube_context,
            target_host: $target_host,
            ktunnel_state: $ktunnel_state,
            nodes: $nodes,
            total: {
              r1m: ([$nodes[] | .r1m] | add // 0),
              r10m: ([$nodes[] | .r10m] | add // 0),
              r1h: ([$nodes[] | .r1h] | add // 0)
            }
          }
      '
      exit 0
    fi

    printf "Context:  ${ctx_color}\e[1m%s\x1b[0m  (%s)\n" "$ctx" "$kube_context"
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
      # shellcheck disable=SC2029  # $ktunnel_svc is expanded locally on purpose
      ssh "$target_host" \
        "SYSTEMD_COLORS=1 systemctl status '$ktunnel_svc' --no-pager -l" \
        2>&1 || true
    fi

    echo ""
    _pod_count=$(jq '.items | length' <<< "$_pods_json")
    if [[ "$_pod_count" -eq 0 ]]
    then
      printf '\e[2m(no miners)\e[0m\n'
    else
      jq -r --argjson workers "$_workers_json" '
        def fmt($n): ($n * 100 | round) / 100 | tostring;
        def age($ts):
          (now - ($ts | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) as $s
          | if $s < 60 then ($s | round | tostring) + "s"
            elif $s < 3600 then ($s / 60 | floor | tostring) + "m"
            elif $s < 86400 then ($s / 3600 | floor | tostring) + "h"
            else ($s / 86400 | floor | tostring) + "d"
            end;
        ($workers.workers | map({key: .[0], value: .}) | from_entries) as $wmap
        | [.items[] | {
            name: .metadata.name,
            status: (.status.phase // "Unknown"),
            restarts: (.status.containerStatuses[0]?.restartCount // 0),
            age: age(.metadata.creationTimestamp),
            node: (.spec.nodeName // "<none>"),
            r1m: ($wmap[.spec.nodeName][8] // 0),
            r10m: ($wmap[.spec.nodeName][9] // 0),
            r1h: ($wmap[.spec.nodeName][10] // 0)
          }] as $rows
        | ([$rows[] | .restarts] | any(. > 0)) as $has_restarts
        | [
            (["NODE", "POD NAME", "STATUS"] +
             (if $has_restarts then ["RESTARTS"] else [] end) +
             ["AGE", "1M(MH/s)", "10M(MH/s)", "1H(MH/s)"]),
            ($rows[] |
             [.node, .name, .status] +
             (if $has_restarts then [.restarts | tostring] else [] end) +
             [.age, fmt(.r1m), fmt(.r10m), fmt(.r1h)]),
            (["TOTAL"] +
             (if $has_restarts then ["", "", "", ""] else ["", "", ""] end) +
             [fmt([$rows[] | .r1m] | add // 0),
              fmt([$rows[] | .r10m] | add // 0),
              fmt([$rows[] | .r1h] | add // 0)])
          ][] | @tsv
      ' <<< "$_pods_json" \
        | column -t -s $'\t' \
        | sed \
            -e '1s/.*/\x1b[1m&\x1b[0m/' \
            -e 's/\bRunning\b/\x1b[32m&\x1b[0m/g' \
            -e 's/\bPending\b/\x1b[33m&\x1b[0m/g' \
            -e 's/\bError\b\|\bCrashLoopBackOff\b\|\bOOMKilled\b/\x1b[1;31m&\x1b[0m/g' \
            -e 's/^TOTAL.*/\x1b[1;36m&\x1b[0m/'
    fi
    ;;

  logs)
    _follow_args=()
    if [[ -n "$follow" ]]
    then
      _follow_args+=(--follow)
    fi

    # Map the optional log target to what to show.
    _lt=$(printf '%s' "$log_target" | tr '[:upper:]' '[:lower:]')
    case "$_lt" in
      "") _target=all ;;
      tun | ktun | tunnel | ktunnel) _target=ktunnel ;;
      x | xm | xmr | xmri | xmrig) _target=xmrig ;;
      *) _target=node ;;
    esac

    _run_xmrig=
    _run_ktunnel=
    case "$_target" in
      all)
        _run_xmrig=1
        # Default also tails ktunnel, but not while following xmrig.
        if [[ -z "$follow" ]]
        then
          _run_ktunnel=1
        fi
        ;;
      xmrig | node)
        _run_xmrig=1
        ;;
      ktunnel)
        _run_ktunnel=1
        ;;
    esac

    if [[ -n "$_run_xmrig" ]]
    then
      if [[ "$_target" == "node" ]]
      then
        echo "=== xmrig pod logs ($ctx / $namespace / node $log_target) ==="
        _pod=$(
          kubectl \
            --kubeconfig "$kube_config" \
            --context "$kube_context" \
            get pods -l app=xmrig -n "$namespace" \
            --field-selector "spec.nodeName=$log_target" \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
        )
        if [[ -z "$_pod" ]]
        then
          red "(no xmrig pod on node $log_target)"
        else
          kubectl \
            --kubeconfig "$kube_config" \
            --context "$kube_context" \
            logs "$_pod" -n "$namespace" --tail=50 \
            "${_follow_args[@]}" 2>/dev/null \
            || red "(no logs)"
        fi
      else
        echo "=== xmrig pod logs ($ctx / $namespace) ==="
        kubectl \
          --kubeconfig "$kube_config" \
          --context "$kube_context" \
          logs -l app=xmrig -n "$namespace" \
          --tail=50 --prefix \
          "${_follow_args[@]}" 2>/dev/null \
          || red "(no logs)"
      fi
    fi

    if [[ -n "$_run_ktunnel" ]]
    then
      if [[ -n "$_run_xmrig" ]]
      then
        echo ""
      fi
      echo "=== ktunnel server pod logs ($ctx / $namespace) ==="
      _pod_json=$(
        kubectl \
          --kubeconfig "$kube_config" \
          --context "$kube_context" \
          get pods -n "$namespace" -o json 2>/dev/null \
          || echo '{"items":[]}'
      )
      # The ktunnel server pod isn't ours to name: it's created by the
      # `ktunnel` binary itself, labelled after the exposed Service (e.g.
      # app.kubernetes.io/name=xmrig-proxy), not "ktunnel". Rather than
      # guessing that name, just pick the pod that isn't our own xmrig
      # DaemonSet worker.
      _ktunnel_pod=$(
        jq -r \
          'first(.items[] | select(.metadata.labels.app != "xmrig") | .metadata.name) // ""' \
          <<< "$_pod_json"
      )
      if [[ -n "$_ktunnel_pod" ]]
      then
        kubectl \
          --kubeconfig "$kube_config" \
          --context "$kube_context" \
          logs "$_ktunnel_pod" -n "$namespace" --tail=50 \
          "${_follow_args[@]}" 2>/dev/null \
          || red "(no logs)"
      else
        red "(ktunnel pod not found)"
      fi

      if [[ -z "$follow" ]]
      then
        echo ""
        echo "=== ktunnel journal ($ctx / $target_host) ==="
        # shellcheck disable=SC2029  # $ktunnel_svc is expanded locally on purpose
        ssh "$target_host" \
          "SYSTEMD_COLORS=1 journalctl -u '$ktunnel_svc' -n 50 --no-pager" \
          2>&1 || red "(unavailable)"
      fi
    fi
    ;;
esac

# vim: set ft=sh et ts=2 sw=2 :
