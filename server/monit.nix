{ lib, config, pkgs, ... }:
# Inspired by https://github.com/dschrempf/blog/blob/7d88061796fb790f0d5b984b62629a68e6882c99/hugo/content/Linux/2024-02-14-Monitoring-a-home-server.md
let
  allowedIps = [ "127.0.0.1" "130.61.39.206" "10.0.0.0/8" "100.64.0.0/10" ];

  resticLastBackup = pkgs.writeShellScript "restic-last-backup" ''
    NOW=$(${pkgs.coreutils}/bin/date +%s)
    LAST_BACKUP=$(/run/current-system/sw/bin/restic-main snapshots --json | \
      ${pkgs.jq}/bin/jq -r '.[-1].time' | \
      ${pkgs.findutils}/bin/xargs -I {} ${pkgs.coreutils}/bin/date -d '{}' '+%s')

    THRESHOLD=''${1:-86400}
    if [[ $((NOW - LAST_BACKUP)) -gt $THRESHOLD ]]
    then
      echo "Last backup was more than $THRESHOLD ago"
      exit 1
    else
      echo -e "Last backup was less than $THRESHOLD ago\n$(date -d "@$LAST_BACKUP")"
      exit 0
    fi
  '';

  monitGeneral = ''
    set daemon 60
    include /etc/monit/conf.d/*

    set httpd port 2812
      allow localhost ${lib.strings.concatMapStringsSep " " (ip: "allow " + ip) allowedIps}'';

  monitSystem = ''
    check system $HOST
      if loadavg (15min) > 4 for 5 times within 15 cycles then alert
      if memory usage > 80% for 4 cycles then alert'';

  monitFilesystem = fs: ''
    check filesystem "filesystem ${fs}" with path ${fs}
        if space usage > 90% then alert'';
  mountPoints = lib.mapAttrsToList (name: fs: fs.mountPoint) config.fileSystems;
  monitFilesystems = lib.strings.concatMapStringsSep "\n" monitFilesystem mountPoints;

  monitRestic = ''
    check program "restic backup status" with path "${resticLastBackup}"
       every 1 cycles
       if status > 0 then alert
       group storage'';
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
      monitRestic
    ];
  };
}
