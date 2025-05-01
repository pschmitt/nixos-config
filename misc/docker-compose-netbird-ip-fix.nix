{ pkgs, ... }:
{
  systemd.services.docker-compose-netbird-ip-fix = {
    description = "Update the netbird ip in docker-compose files";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.bash
      pkgs.findutils
      pkgs.gnused
      pkgs.jq
      pkgs.docker-compose
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

        find -L /srv -maxdepth 2 -iname docker-compose.yaml -exec sh -c '
          file="$1"
          netbird_ip="$2"

          checksum1=$(sha256sum "$file")
          sed -r -i "s#100\.122\.[0-9]+\.[0-9]+#''${netbird_ip}#g" "$file"
          checksum2=$(sha256sum "$file")

          if [[ "$checksum1" != "$checksum2" ]]
          then
            echo "$file"
          fi
        ' -- {} "$netbird_ip" \;
      }

      if ! NETBIRD_IP=$(netbird_ip) || [[ -z "$NETBIRD_IP" ]]
      then
        echo "Failed to determine Netbird IP" >&2
        exit 1
      fi

      echo "Updating all compose files in /srv to bind to $NETBIRD_IP"

      mapfile -t UPDATED_FILES < <(patch_compose_files "$NETBIRD_IP")
      for COMPOSE_FILE in "''${UPDATED_FILES[@]}"
      do
        echo "Updated $COMPOSE_FILE"
        echo "Restarting services..."
        docker-compose -f $COMPOSE_FILE up --force-recreate -d
      done
    '';
  };

  systemd.timers.docker-compose-netbird-ip-fix = {
    description = "Fix netbird IPs in docker-compose files";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
