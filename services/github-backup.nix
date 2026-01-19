{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/github-backup";

  githubLastBackup = pkgs.writeShellScript "github-last-backup" ''
    THRESHOLD=''${1:-86400}
    NOW=$(${pkgs.coreutils}/bin/date '+%s')

    LAST_BACKUP=$(cat ${dataDir}/data/LAST_UPDATED | \
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
in
{
  sops.secrets = {
    "github-backup/env" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-github-backup.service" ];
    };
    "github-backup/ssh/privkey" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-github-backup.service" ];
    };
    "github-backup/ssh/pubkey" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-github-backup.service" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir}      0750 root root - -"
    "d ${dataDir}/data 0750 root root - -"
  ];

  virtualisation.oci-containers.containers.github-backup = {
    autoStart = true;
    image = "ghcr.io/pschmitt/github-backup:latest";
    pull = "always";
    environmentFiles = [
      config.sops.secrets."github-backup/env".path
    ];
    environment = {
      GITHUB_USERNAME = "pschmitt";
      INTERVAL = "1d";
      GITHUB_BACKUP_ARGS = "--throttle-limit=5000 --throttle-pause=0.72";
    };
    volumes = [
      "${dataDir}/data:/data"
      "${config.sops.secrets."github-backup/ssh/privkey".path}:/ssh/id_github-backup_ed25519:ro"
      "${config.sops.secrets."github-backup/ssh/pubkey".path}:/ssh/id_github-backup_ed25519.pub:ro"
    ];
  };

  services.monit.config = lib.mkAfter ''
    check program "github-backup" with path "${githubLastBackup}"
      group backup
      every 2 cycles
      if status > 0 then alert
  '';
}
