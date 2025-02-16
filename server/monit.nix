{
  lib,
  config,
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

  monitGeneral = ''
    set daemon 60
    include /etc/monit/conf.d/*
  '';

  monitSystem = ''
    check system $HOST
      if loadavg (15min) per core > 1 for 5 times within 15 cycles then alert
      if memory usage > 80% for 4 cycles then alert
      if uptime < 1 hours then alert
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
      if status > 0 then alert'';

  monitTailscale = ''
    check network tailscale with interface tailscale0
      group "network"
      restart program = "${pkgs.systemd}/bin/systemctl restart tailscaled"
      if link down for 2 cycles then restart
      if 5 restarts within 10 cycles then alert

    check host tailscale-magicdns with address 100.100.100.100
      group "network"
      depends on "tailscale"
      restart program = "${pkgs.systemd}/bin/systemctl restart tailscaled"
      if failed ping for 2 cycles then restart
      if 3 restarts within 10 cycles then alert
  '';

  monitNetbird = ''
    check network netbird with interface nb-netbird-io
      group "network"
      restart program = "${pkgs.systemd}/bin/systemctl restart netbird-netbird-io"
      if link down for 2 cycles then restart
      if 5 restarts within 10 cycles then alert
  '';

  monitZeroTier = ''
    check network zerotier with interface ztbtosdaym
      group "network"
      restart program = "${pkgs.systemd}/bin/systemctl restart zerotier-one"
      if link down for 2 cycles then restart
      if 5 restarts within 10 cycles then alert
  '';

  monitNetwork = lib.strings.concatStringsSep "\n" [
    monitNetbird
    monitTailscale
    monitZeroTier
  ];

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
  config = lib.mkIf (!config.custom.cattle) {
    sops.secrets."monit/config" = { };
    environment.etc."monit/conf.d/secret-config".source = "${config.sops.secrets."monit/config".path}";

    services.monit = {
      # Do not enable monit if cattle if this is a cattle server
      enable = true;
      config = lib.strings.concatStringsSep "\n" [
        monitGeneral
        monitSystem
        monitFilesystems
        monitNetwork
        monitRestic
      ];
    };

    systemd.services.monit.after = [
      "tailscaled.service"
      "netbird-netbird-io.service"
    ];
    systemd.services.monit.preStart = "${renderMonitConfig}";
  };
}
