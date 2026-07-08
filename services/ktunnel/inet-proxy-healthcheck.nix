# End-to-end healthcheck for a ktunnel-exposed inet-proxy instance.
#
# The ktunnel server image is a minimal scratch container with no shell, so
# `kubectl exec` can't run a check inside it. Instead this uses
# `kubectl port-forward`, which proxies raw TCP to the pod purely from the
# client side (no shell needed in the pod), to reach the ktunnel-created
# Deployment's port, then makes an actual proxied HTTPS request through it.
# That exercises the full path: kubectl API -> ktunnel server pod ->
# gRPC tunnel -> rofl-12 -> local tinyproxy -> internet, which is exactly
# where the known failure mode bites (see services/ktunnel/expose.nix): the
# ktunnel client can end up "active (running)" with its local listener
# silently dead after losing the gRPC stream to its pod.
{ pkgs }:
{
  mkCheckScript =
    name:
    {
      kubeconfig,
      namespace,
      serviceName,
      port,
      # Local port used only transiently for the port-forward during the
      # check. Callers should pass something derived from their own
      # tunnelPort so concurrent instances on the same host never collide.
      checkPort,
    }:
    pkgs.writeShellScript "ktunnel-inet-proxy-healthcheck-${name}.sh" ''
      set -u
      export KUBECONFIG=${kubeconfig}
      prefix="ktunnel-inet-proxy-${name}:"
      pf_log=$(${pkgs.coreutils}/bin/mktemp)
      trap '[ -n "''${pf_pid:-}" ] && kill "$pf_pid" 2>/dev/null; wait "''${pf_pid:-}" 2>/dev/null; rm -f "$pf_log"' EXIT

      ${pkgs.kubectl}/bin/kubectl -n ${namespace} port-forward "deploy/${serviceName}" \
        "${toString checkPort}:${toString port}" >"$pf_log" 2>&1 &
      pf_pid=$!

      established=0
      for _ in $(seq 1 10); do
        if ${pkgs.gnugrep}/bin/grep -q "Forwarding from" "$pf_log" 2>/dev/null; then
          established=1
          break
        fi
        sleep 0.5
      done

      if [ "$established" -ne 1 ]; then
        echo "$prefix cannot verify tunnel health: kubectl port-forward to deploy/${serviceName} in ${namespace} never came up: $(cat "$pf_log")" >&2
        echo "$prefix assuming healthy for now to avoid restarting over an unrelated kubectl/API problem"
        exit 0
      fi

      http_code=$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' \
        -x "http://127.0.0.1:${toString checkPort}" --max-time 10 https://1.1.1.1 2>/dev/null)

      if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
        echo "$prefix tunnel healthy: got HTTP $http_code through the proxy"
        exit 0
      fi

      echo "$prefix tunnel looks dead: a request through kubectl port-forward -> ktunnel -> tinyproxy failed (http_code=''${http_code:-<empty>})" >&2
      exit 1
    '';
}
