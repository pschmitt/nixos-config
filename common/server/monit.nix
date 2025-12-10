{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Inspired by https://github.com/dschrempf/blog/blob/7d88061796fb790f0d5b984b62629a68e6882c99/hugo/content/Linux/2024-02-14-Monitoring-a-home-server.md
let
  resticLastBackup = pkgs.writeShellScript "restic-last-backup" ''
    THRESHOLD=''${1:-86400}
    NOW=$(${pkgs.coreutils}/bin/date '+%s')

    LAST_BACKUP=$(/run/current-system/sw/bin/restic-main snapshots --json | \
      ${pkgs.jq}/bin/jq -r '.[-1].time' | \
      ${pkgs.findutils}/bin/xargs -I {} ${pkgs.coreutils}/bin/date -d '{}' '+%s')

    if [[ $((NOW - LAST_BACKUP)) -gt $THRESHOLD ]]
    then
      echo "🚨 Last backup was more than $THRESHOLD ago"
      echo -e "📅 $(date -d "@$LAST_BACKUP")"
      exit 1
    else
      echo -e "✅ Last backup was less than $THRESHOLD ago"
      echo -e "📅 $(date -d "@$LAST_BACKUP")"
      exit 0
    fi
  '';

  needsReboot = pkgs.writeShellScript "needs-reboot" ''
    OUTPUT=$(${
      inputs.nixos-needsreboot.packages.${pkgs.stdenv.hostPlatform.system}.default
    }/bin/nixos-needsreboot 2>&1 | ${pkgs.strip-ansi}/bin/strip-ansi)
    echo "$OUTPUT"
    ${pkgs.gnugrep}/bin/grep -q 'Reboot not required' <<< "$OUTPUT"
  '';

  failedTimers = pkgs.writeShellScript "failed-systemd-timers" ''
    SYSTEMCTL=${pkgs.systemd}/bin/systemctl

    TIMER_LINES=$($SYSTEMCTL \
      list-timers \
      --all \
      --output=json \
      --no-pager \
      | ${pkgs.jq}/bin/jq -er '
        .[] | select(.last != 0) | [.unit, (.activates // "")] | @tsv
      '
    )

    if [[ -z "$TIMER_LINES" ]]
    then
      echo "✅ No systemd timers found."
      exit 0
    fi

    FAILURES=()

    while IFS=$'\t' read -r TIMER SERVICE
    do
      if [[ -z "$TIMER" || -z "$SERVICE" ]]
      then
        continue
      fi

      RESULT=$($SYSTEMCTL show "$SERVICE" --property=Result --value)
      STATE=$($SYSTEMCTL show "$SERVICE" --property=ActiveState --value)

      if [[ "$RESULT" != "success" || "$STATE" == "failed" ]]
      then
        FAILURES+=("$TIMER -> $SERVICE (result=$RESULT state=$STATE)")
      fi
    done <<< "$TIMER_LINES"

    if [[ ''${#FAILURES[@]} -eq 0 ]]
    then
      echo "✅ No failed systemd timer targets detected."
      exit 0
    fi

    echo "🚨 Failed systemd timer targets detected:"
    printf '%s\n' "''${FAILURES[@]}"
    exit 1
  '';

  failedServices = pkgs.writeShellScript "failed-systemd-services" ''
    SYSTEMCTL=${pkgs.systemd}/bin/systemctl

    FAILED_SERVICES=$($SYSTEMCTL \
      --failed \
      --type=service \
      --output=json \
      --no-pager \
      | ${pkgs.jq}/bin/jq -r '
        .[] | select((.active // "") == "failed" or (.sub // "") == "failed")) | .unit
      ' \
    )

    if [[ -z "$FAILED_SERVICES" ]]
    then
      echo "✅ No failed systemd services detected."
      exit 0
    fi

    echo "🚨 Failed systemd services detected:"
    echo "$FAILED_SERVICES"
    exit 1
  '';

  monitGeneral = ''
    set daemon 60
    include /etc/monit/conf.d/*

    # https://mmonit.com/monit/documentation/monit.html#LIMITS
    set limits {
      # check program's output truncate limit, default: 512 B
      programOutput:     1 MB,

      # limit for send/expect protocol test, default: 256 B
      sendExpectBuffer:  1 MB,

      # limit for file content test, default: 512 B
      fileContentBuffer: 1 MB,

      # limit for HTTP content test, default: 1 MB
      httpContentBuffer: 2 MB,

      # timeout for network I/O, default: 5 s
      networkTimeout:    20 s,

      # timeout for check program, default: 300 s
      programTimeout:    300 s,

      # timeout for service stop, default: 30 s
      stopTimeout:       120 s,

      # timeout for service start, default: 30 s
      startTimeout:      300 s,

      # timeout for service restart, default: 30 s
      restartTimeout:    600 s
    }
  '';

  monitSystem = ''
    check system $HOST
      if loadavg (15min) per core > 1 for 5 times within 15 cycles then alert
      if memory usage > 80% for 4 cycles then alert
      if uptime < 1 hours then alert
  '';

  monitRebootRequired = ''
    check program "Reboot required" with path "${needsReboot}"
      group system
      every 2 cycles
      if status > 0 then alert
  '';

  monitFailedTimers = ''
    check program "Systemd timers" with path "${failedTimers}"
      group system
      if status > 0 then alert
  '';

  monitFailedServices = ''
    check program "Systemd services" with path "${failedServices}"
      group system
      if status > 0 then alert
  '';

  monitFilesystem = fs: ''
    check filesystem "filesystem ${fs}" with path ${fs}
      group storage
      if space usage > 85% then alert'';
  # Below will exclude NFS and bind mounts
  nonNFSFileSystems = lib.filterAttrs (
    name: fs: fs.fsType != "nfs" && !lib.elem "bind" (fs.options or [ ])
  ) config.fileSystems;
  mountPoints = lib.mapAttrsToList (name: fs: fs.mountPoint) nonNFSFileSystems;
  monitFilesystems = lib.strings.concatMapStringsSep "\n" monitFilesystem mountPoints;

  monitRestic = ''
    check program "restic backup status" with path "${resticLastBackup}"
      group storage
      every 5 cycles
      if status > 0 then alert
  '';

  renderMonitConfig = pkgs.writeShellScript "render-monit-config" ''
    MONIT_CONF_DIR=/etc/monit/conf.d
    mkdir -p "$MONIT_CONF_DIR"

    MAIN_NIC=$(${pkgs.iproute2}/bin/ip --json route | \
      ${pkgs.jq}/bin/jq -r '
        [[.[] | select(.dst == "default")] | sort_by(.metric)[] | .dev][0]
      ')

    if [[ -z "$MAIN_NIC" || "$MAIN_NIC" == "null" ]]
    then
      echo "WARNING: failed to determine main network interface. Trying to find the first physical nic." >&2
      MAIN_NIC=$(${pkgs.iproute2}/bin/ip -j link show | \
        ${pkgs.jq}/bin/jq -er '
          [.[] | select(.link_type == "ether" and (.ifname | test("docker") | not))][0].ifname
        ')
    fi

    if [[ -z "$MAIN_NIC" || "$MAIN_NIC" == "null" ]]
    then
      echo "ERROR: failed to determine main network interface" >&2
      exit 0
    fi

    cat > "$MONIT_CONF_DIR/network" <<EOF
    check network main-nic with interface $MAIN_NIC
      group "network"
      if link down then alert
    EOF
  '';
in
{
  sops = {
    secrets = {
      "monit/config/httpd" = { };
      "monit/config/mmonit" = { };
    };

    templates.monitSecretConfig = {
      content = builtins.concatStringsSep "\n" [
        # only include the mmonit config if this is not a cattle server
        (lib.optionalString (!config.hardware.cattle) config.sops.placeholder."monit/config/mmonit")
        config.sops.placeholder."monit/config/httpd"
      ];

      mode = "0400";
      owner = "root";
      group = "root";
    };
  };

  environment.etc = {
    "monit/conf.d/secret-config".source = config.sops.templates.monitSecretConfig.path;
  };

  services.monit = {
    # Do not enable monit if cattle if this is a cattle server
    enable = true;
    config = lib.strings.concatStringsSep "\n" [
      monitGeneral
      monitSystem
      monitRebootRequired
      monitFailedTimers
      monitFailedServices
      monitFilesystems
      monitRestic
    ];
  };

  systemd.services.monit.preStart = "${renderMonitConfig}";
}
