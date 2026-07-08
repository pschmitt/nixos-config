{ pkgs }:
{
  # Considers a worker's last report stale after this long. Generous
  # relative to the 5min default healthcheck interval so low-hashrate CPU
  # workers (which submit shares far less often than GPU ones) don't
  # trigger a false-positive restart.
  staleAfterMs = 10 * 60 * 1000;

  # Pure connectivity check for one ktunnel-xmrig-proxy instance. Prints a
  # single, self-explanatory status line and exits 0 if the tunnel looks
  # healthy (or can't be verified for a reason unrelated to the tunnel
  # itself, e.g. a transient kubectl/API hiccup) or 1 if it looks dead.
  #
  # Callers decide what to do about a failure: the systemd healthcheck
  # timer restarts the service directly, monit's "restart program" action
  # does so via its own retry/alerting policy.
  mkCheckScript =
    name: inst: staleAfterMs:
    pkgs.writeShellScript "ktunnel-xmrig-proxy-healthcheck-${name}.sh" ''
      set -u
      export KUBECONFIG=${inst.kubeconfig}
      prefix="ktunnel-xmrig-proxy-${name}:"

      # Only re-run (read-only, cheap) to capture stderr for the message on
      # failure -- merging streams unconditionally would let harmless
      # warnings on stderr (e.g. kubectl's "kuberc: ... permission denied"
      # when $HOME isn't writable) corrupt the JSON we parse on success.
      pods_output=$(${pkgs.kubectl}/bin/kubectl get pods -n ${inst.namespace} -l app=xmrig -o json 2>/dev/null)
      kubectl_rc=$?
      if [ "$kubectl_rc" -ne 0 ]
      then
        kubectl_err=$(${pkgs.kubectl}/bin/kubectl get pods -n ${inst.namespace} -l app=xmrig -o json 2>&1 >/dev/null)
        echo "$prefix cannot verify tunnel health: kubectl failed to list xmrig pods (exit $kubectl_rc): $kubectl_err" >&2
        echo "$prefix assuming healthy for now to avoid restarting over an unrelated kubectl/API problem"
        exit 0
      fi

      nodes_json=$(${pkgs.jq}/bin/jq -c '[.items[].spec.nodeName] | unique' <<< "$pods_output")
      node_count=$(${pkgs.jq}/bin/jq 'length' <<< "$nodes_json")

      if [ "$node_count" -eq 0 ]
      then
        echo "$prefix no xmrig pods found in namespace ${inst.namespace}, nothing to verify yet"
        exit 0
      fi

      workers_output=$(${pkgs.curl}/bin/curl -sSf http://127.0.0.1:9674/1/workers 2>/dev/null)
      curl_rc=$?
      if [ "$curl_rc" -ne 0 ]
      then
        curl_err=$(${pkgs.curl}/bin/curl -sSf http://127.0.0.1:9674/1/workers 2>&1 >/dev/null)
        echo "$prefix cannot verify tunnel health: failed to query the shared xmrig-proxy API (curl exit $curl_rc): $curl_err" >&2
        echo "$prefix assuming healthy for now to avoid restarting over an unrelated proxy-API problem"
        exit 0
      fi

      now_ms=$(($(${pkgs.coreutils}/bin/date +%s%N) / 1000000))

      # One "<node>\ttrue|false" line per xmrig node, so we can name names
      # in the status message instead of just giving a yes/no verdict.
      per_node=$(
        ${pkgs.jq}/bin/jq -r \
          --argjson nodes "$nodes_json" \
          --argjson now "$now_ms" \
          --argjson stale_after ${toString staleAfterMs} '
          (.workers // []) as $ws
          | $nodes[] as $n
          | [$n, ($ws | any(.[0] == $n and .[2] == 1 and (($now - .[7]) < $stale_after)))]
          | @tsv
        ' <<< "$workers_output"
      )

      connected_nodes=$(${pkgs.gawk}/bin/awk -F'\t' '$2 == "true" { print $1 }' <<< "$per_node")
      connected_count=$(${pkgs.gnugrep}/bin/grep -c . <<< "$connected_nodes")

      if [ "$connected_count" -gt 0 ]
      then
        echo "$prefix tunnel healthy: $connected_count/$node_count xmrig node(s) connected via the shared proxy (e.g. $(${pkgs.coreutils}/bin/head -1 <<< "$connected_nodes"))"
        exit 0
      fi

      node_list=$(${pkgs.jq}/bin/jq -r 'join(", ")' <<< "$nodes_json")
      echo "$prefix tunnel looks dead: none of the $node_count xmrig node(s) ($node_list) have reported to the shared proxy in the last ${
        toString (staleAfterMs / 60000)
      } minutes" >&2
      exit 1
    '';
}
