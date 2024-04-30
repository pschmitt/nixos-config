{ lib, config, pkgs, ... }:
# Inspired by https://github.com/dschrempf/blog/blob/7d88061796fb790f0d5b984b62629a68e6882c99/hugo/content/Linux/2024-02-14-Monitoring-a-home-server.md
let
  allowList = [
    "mmonit.heimat.dev"
    "mmonit.oci-03.heimat.dev"
    "localhost"
    "127.0.0.1"
    "10.0.0.0/8"
    "100.64.0.0/10"
  ];

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

    set httpd port 2812
      ${lib.strings.concatMapStringsSep " " (ip: "allow " + ip) allowList}'';

  monitSystem = ''
    check system $HOST
      if loadavg (15min) per core > 1 for 5 times within 15 cycles then alert
      if memory usage > 80% for 4 cycles then alert'';

  monitFilesystem = fs: ''
    check filesystem "filesystem ${fs}" with path ${fs}
      group storage
      if space usage > 85% then alert'';
  mountPoints = lib.mapAttrsToList (name: fs: fs.mountPoint) config.fileSystems;
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
      if link down then restart
      if 5 restarts within 10 cycles then alert

    check host tailscale-magicdns with address 100.100.100.100
      group "network"
      depends on "tailscale"
      restart program = "${pkgs.systemd}/bin/systemctl restart tailscaled"
      if failed ping for 2 cycles then restart
      if 3 restarts within 10 cycles then alert
  '';

  monitNetbird = ''
    check network netbird with interface netbird-io
      group "network"
      restart program = "${pkgs.systemd}/bin/systemctl restart netbird-netbird-io"
      if link down then restart
      if 5 restarts within 10 cycles then alert
  '';

  monitNetwork = lib.strings.concatStringsSep "\n" [
    monitTailscale
    monitNetbird
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
  age.secrets.mmonit-monit-config.file = ../secrets/mmonit-monit-config.age;
  environment.etc."monit/conf.d/mmonit".source = "${config.age.secrets.mmonit-monit-config.path}";

  services.monit = {
    enable = true;
    config = lib.strings.concatStringsSep "\n" [
      monitGeneral
      monitSystem
      monitFilesystems
      monitNetwork
      monitRestic
    ];
  };

  systemd.services.monit.preStart = "${renderMonitConfig}";
}
