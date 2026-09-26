{
  config,
  lib,
  pkgs,
}:
ports:
let
  backend = config.virtualisation.oci-containers.backend;

  mkForward =
    name: port: iface:
    let
      addressCommand =
        if iface == "netbird" then
          "/run/current-system/sw/bin/netbird-netbird-io status --json | ${pkgs.jq}/bin/jq -er '.netbirdIp | gsub(\"/.*\"; \"\")'"
        else
          "${config.services.tailscale.package}/bin/tailscale ip -4";
      unitName = "mesh-port-forward-${name}-${iface}";
    in
    {
      name = unitName;
      value = {
        description = "Forward ${name} port ${toString port} over ${iface}";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "netbird-netbird-io-autoconnect.service"
          "tailscaled-autoconnect.service"
        ];
        after = [
          "network-online.target"
          "netbird-netbird-io-autoconnect.service"
          "tailscaled-autoconnect.service"
          "${backend}-${name}.service"
        ];
        partOf = [
          "netbird-netbird-io.service"
          "tailscaled.service"
        ];
        serviceConfig = {
          ExecStart = pkgs.writeShellScript unitName ''
            set -euo pipefail
            for attempt in {1..60}
            do
              if IP=$(${addressCommand}) && [[ -n $IP ]]
              then
                exec ${pkgs.socat}/bin/socat \
                  "TCP4-LISTEN:${toString port},bind=$IP,reuseaddr,fork" \
                  "TCP4:127.0.0.1:${toString port}"
              fi

              ${pkgs.coreutils}/bin/sleep 1
            done

            echo "Failed to determine ${iface} IP for ${name}" >&2
            exit 1
          '';
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };
    };
in
lib.listToAttrs (
  lib.concatMap (
    name:
    map (iface: mkForward name ports.${name} iface) [
      "tailscale"
      "netbird"
    ]
  ) (lib.attrNames ports)
)
