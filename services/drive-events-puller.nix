# Near-instant sync trigger for a Google Drive folder.
#
# Drive pushes "file created/moved/changed" events (Workspace Events API) to a
# Pub/Sub topic. A puller pulls them and touches a trigger file; a systemd path
# unit then starts `triggerUnit`. A daily timer keeps the Workspace Events
# subscription alive (they expire after at most a week).
#
# All identifiers and credentials come from `environmentFile` / `credentialsFile`
# (set from the private repository); nothing identifying lives here.
#
# environmentFile must define:
#   DRIVE_EVENTS_PROJECT, DRIVE_EVENTS_SUBSCRIPTION      (puller)
#   EVENTS_PROJECT, EVENTS_TOPIC, EVENTS_FOLDER_ID,
#   OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, OAUTH_REFRESH_TOKEN  (renewal)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.drive-events-puller;
  user = "drive-events-puller";
  triggerDir = "/run/drive-events-puller";
  triggerFile = "${triggerDir}/trigger";

  puller = pkgs.writers.writePython3Bin "drive-events-puller" {
    libraries = [ pkgs.python3Packages.google-cloud-pubsub ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/drive-events-puller.py);

  renew = pkgs.writeShellApplication {
    name = "drive-events-renew";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/drive-events-renew.sh;
  };
in
{
  options.services.drive-events-puller = {
    enable = lib.mkEnableOption "Google Drive event puller that triggers a sync unit";

    environmentFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path to an env file with the settings listed in this module's header.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path to the Pub/Sub service account key (JSON) used by the puller.";
    };

    triggerUnit = lib.mkOption {
      type = lib.types.str;
      default = "rclone-bisync-incoming.service";
      description = "Unit started whenever Drive events arrive.";
    };

    debounceSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Quiet period after the last event before triggering, so multi-page scans coalesce.";
    };

    renewCalendar = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "How often to renew the Workspace Events subscription.";
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      users.${user} = {
        isSystemUser = true;
        group = user;
      };
      groups.${user} = { };
    };

    systemd = {
      tmpfiles.rules = [ "d ${triggerDir} 0755 ${user} ${user} -" ];

      services = {
        drive-events-puller = {
          description = "Pull Google Drive events from Pub/Sub";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          environment = {
            DRIVE_EVENTS_TRIGGER_FILE = triggerFile;
            DRIVE_EVENTS_DEBOUNCE_SECONDS = toString cfg.debounceSeconds;
            GOOGLE_APPLICATION_CREDENTIALS = "%d/credentials";
          };

          serviceConfig = {
            ExecStart = lib.getExe puller;
            EnvironmentFile = cfg.environmentFile;
            LoadCredential = "credentials:${cfg.credentialsFile}";
            User = user;
            Group = user;
            Restart = "always";
            RestartSec = "10s";
            ReadWritePaths = [ triggerDir ];
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
          };
        };

        drive-events-renew = {
          description = "Renew the Google Drive Workspace Events subscription";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe renew;
            EnvironmentFile = cfg.environmentFile;
            User = user;
            Group = user;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };
      };

      paths.drive-events-trigger = {
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = triggerFile;
          Unit = cfg.triggerUnit;
        };
      };

      timers.drive-events-renew = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.renewCalendar;
          RandomizedDelaySec = "30min";
          Persistent = true;
        };
      };
    };
  };
}
