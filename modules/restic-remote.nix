{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.restic-remote;

  instanceOptions =
    { name, config, ... }:
    {
      options = {
        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "SSH User";
        };

        host = lib.mkOption {
          type = lib.types.str;
          description = "SSH Host";
        };

        identityFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to SSH private key";
        };

        timer = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "Systemd timer schedule (OnCalendar)";
        };

        environmentFile = lib.mkOption {
          type = lib.types.path;
          description = "File containing secrets (env vars). Should include RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS credentials, and optionally HEALTHCHECK_URL.";
        };

        repositoryFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing restic repository URL. If null, RESTIC_REPOSITORY must be set in environmentFile.";
        };

        exclude = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Paths to exclude from backup";
        };

        pruneOpts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "--keep-last 5"
            "--keep-daily 1"
            "--keep-weekly 2"
            "--keep-monthly 3"
            "--keep-yearly 10"
            "--keep-within 14d"
          ];
          description = "Prune options for restic";
        };

        extraOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra options to pass to restic";
        };
      };
    };
in
{
  options.services.restic-remote = {
    enable = lib.mkEnableOption "restic-remote backup service";

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceOptions);
      default = { };
      description = "Backup instances";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secrets configuration
    sops.secrets = lib.mkMerge (
      lib.mapAttrsToList (name: _instance: {
        "restic-remote/${name}/env" = config.custom.mkSecret {
        };
        "restic-remote/${name}/sshkey" = config.custom.mkSecret {
        };
      }) cfg.instances
    );

    fileSystems = lib.mkMerge (
      lib.mapAttrsToList (name: instance: {
        "/var/lib/restic-remote/mounts/${name}" = {
          fsType = "fuse";
          device = "${pkgs.sshfs-fuse}/bin/sshfs#${instance.user}@${instance.host}:/";
          options = [
            "noauto"
            "_netdev"
            "allow_other"
            "reconnect"
            "follow_symlinks"
            "x-systemd.automount"
            "x-systemd.device-timeout=10s"
            "x-systemd.mount-timeout=10s"
            "IdentityFile=${instance.identityFile}"
            "UserKnownHostsFile=/dev/null"
            "ServerAliveInterval=10"
            "BatchMode=yes"
            "PasswordAuthentication=no"
            # "StrictHostKeyChecking=no"
          ];
        };
      }) cfg.instances
    );

    environment.systemPackages = [
      pkgs.restic
      pkgs.sshfs
    ];

    services.restic.backups = lib.mapAttrs' (
      name: instance:
      let
        mountDir = "/var/lib/restic-remote/mounts/${name}";
        # Back up the mount directory itself (which contains the entire remote filesystem)
        backupPaths = [ mountDir ];
        # Translate remote excludes to mount-relative paths
        excludePaths = map (p: "${mountDir}${p}") instance.exclude;

        healthcheckScript = suffix: ''
          if [ -n "''${HEALTHCHECK_URL:-}" ]; then
            ${pkgs.curl}/bin/curl -fsSL -m 10 --retry 5 -X POST \
              -H "Content-Type: text/plain" \
              --data "restic-remote ${name}: backup ${suffix}" \
              "$HEALTHCHECK_URL${suffix}" || true
          fi
        '';
      in
      lib.nameValuePair name (
        {
          inherit (instance)
            pruneOpts
            extraOptions
            environmentFile
            ;
          paths = backupPaths;
          exclude = excludePaths;

          extraBackupArgs = [
            "--host"
            instance.host
          ];

          timerConfig = {
            OnCalendar = instance.timer;
            RandomizedDelaySec = "600";
            Persistent = true;
          };

          backupPrepareCommand = ''
            # Ensure mount directory exists
            mkdir -p ${mountDir}

            # Wait for mount to be ready (automount should handle this)
            for i in {1..30}; do
              if ${pkgs.util-linux}/bin/mountpoint -q ${mountDir}
              then
                echo "Mount ${mountDir} is ready"
                break
              fi
              echo "Waiting for mount ${mountDir}... ($i/30)"
              # Trigger automount by accessing the directory
              ls ${mountDir} > /dev/null 2>&1 || true
              sleep 2
            done

            if ! ${pkgs.util-linux}/bin/mountpoint -q ${mountDir}
            then
              echo "ERROR: Mount ${mountDir} is not available after 60 seconds"
              ${healthcheckScript "/fail"}
              exit 1
            fi

            ${healthcheckScript "/start"}
          '';

          backupCleanupCommand = healthcheckScript "";
        }
        // lib.optionalAttrs (instance.repositoryFile != null) {
          inherit (instance) repositoryFile;
        }
      )
    ) cfg.instances;

    # Override the systemd service to add failure handling and create failure notification services
    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: instance:
        lib.nameValuePair "restic-backups-${name}" {
          serviceConfig = {
            TimeoutStartSec = "4h";
          };
          onFailure = [ "restic-backups-${name}-failure.service" ];
        }
      ) cfg.instances)
      (lib.mkMerge (
        lib.mapAttrsToList (name: instance: {
          "restic-backups-${name}-failure" = {
            description = "Healthcheck notification for failed ${name} backup";
            serviceConfig = {
              Type = "oneshot";
              EnvironmentFile = instance.environmentFile;
            };
            script = ''
              if [ -n "''${HEALTHCHECK_URL:-}" ]; then
                ${pkgs.curl}/bin/curl -fsSL -m 10 --retry 5 -X POST \
                  -H "Content-Type: text/plain" \
                  --data "restic-remote ${name}: backup failed" \
                  "$HEALTHCHECK_URL/fail" || true
              fi
            '';
          };
        }) cfg.instances
      ))
    ];
  };
}
