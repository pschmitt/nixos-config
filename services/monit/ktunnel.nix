{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mapAttrsToList concatStringsSep;

  cfg = config.services.ktunnel-xmrig-proxy;
  instances = lib.filterAttrs (_: inst: inst.enable) cfg;

  # Considers a worker's last report stale after this long. Mirrors the
  # threshold used by the ktunnel-xmrig-proxy healthcheck timer.
  workerStaleAfterMs = 10 * 60 * 1000;

  checkScript =
    name: inst:
    pkgs.writeShellScript "ktunnel-xmrig-proxy-monit-check-${name}.sh" ''
      set -u
      export KUBECONFIG=${inst.kubeconfig}

      nodes_json=$(
        ${pkgs.kubectl}/bin/kubectl get pods -n ${inst.namespace} -l app=xmrig -o json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -c '[.items[].spec.nodeName] | unique' \
          || echo '[]'
      )
      workers_json=$(${pkgs.curl}/bin/curl -sf http://127.0.0.1:9674/1/workers 2>/dev/null || echo '{"workers":[]}')
      now_ms=$(($(date +%s%N) / 1000000))

      healthy=$(
        ${pkgs.jq}/bin/jq -r \
          --argjson nodes "$nodes_json" \
          --argjson now "$now_ms" \
          --argjson stale_after ${toString workerStaleAfterMs} '
          (.workers // []) as $ws
          | ($nodes // []) as $ns
          | ($ns | length) == 0
            or any($ns[]; . as $n | $ws | any(.[0] == $n and .[2] == 1 and (($now - .[7]) < $stale_after)))
        ' <<< "$workers_json"
      )

      if [ "$healthy" = "true" ]
      then
        echo "at least one worker reachable (or no xmrig pods found yet)"
        exit 0
      fi

      echo "no worker for nodes $nodes_json reported in via the shared proxy in the last ${
        toString (workerStaleAfterMs / 60000)
      } minutes" >&2
      exit 1
    '';

  monitInstance = name: inst: ''
    check program "ktunnel ${name}" with path "${checkScript name inst}"
      group "network"
      group "ktunnel"
      restart program = "${pkgs.systemd}/bin/systemctl restart ktunnel-xmrig-proxy-${name}.service"
      # NOTE: program checks run async -- monit evaluates the *previous*
      # run's exit code each cycle. With a bare "then restart" a single
      # transient failure restarts the service, the next run executes
      # while it's still coming up, fails and restarts it again -- forever.
      if status != 0 for 2 cycles then restart
      # recovery
      else if succeeded then exec "${pkgs.coreutils}/bin/true"
      if 5 restarts within 10 cycles then alert
  '';

  monitKtunnel = concatStringsSep "\n" (mapAttrsToList monitInstance instances);
in
{
  services.monit.config = lib.mkAfter monitKtunnel;

  systemd.services.monit.after = mapAttrsToList (
    name: _: "ktunnel-xmrig-proxy-${name}.service"
  ) instances;
}
