{ pkgs, ... }:
{
  systemd.services.docker-compose-netbird-ip-fix = {
    description = "Update the netbird ip in docker-compose files";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.findutils
      pkgs.gnused
      pkgs.jq
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      netbird_ip() {
        # FIXME We should use the pkgs.netbird-netbird-io path here...
        /run/current-system/sw/bin/netbird-netbird-io status --json | \
          jq -er '.netbirdIp | gsub("/.*"; "")'
      }

      patch_compose_files() {
        local netbird_ip="''${1:-$(netbird_ip)}"

        if [[ -z "$netbird_ip" ]]
        then
          echo "Failed to determine Netbird IP" >&2
          return 1
        fi

        find -L /srv -maxdepth 2 -iname docker-compose.yaml -exec \
          sed -r -i "s#100\.122\.[0-9]+\.[0-9]+#''${netbird_ip}#g" {} \;
      }

      if ! NETBIRD_IP=$(netbird_ip) || [[ -z "$NETBIRD_IP" ]]
      then
        echo "Failed to determine Netbird IP" >&2
        exit 1
      fi

      echo "Updating all compose files in /srv to bind to $NETBIRD_IP"

      patch_compose_files "$NETBIRD_IP"
    '';
  };

  systemd.timers.docker-compose-netbird-ip-fix = {
    description = "Fix netbird IPs in docker-compose files";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
