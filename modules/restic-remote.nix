{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.restic-remote;

  instanceOptions =
    { name, config, ... }:
    {
      options = {
        user = mkOption {
          type = types.str;
          default = "root";
          description = "SSH User";
        };

        host = mkOption {
          type = types.str;
          description = "SSH Host";
        };

        identityFile = mkOption {
          type = types.path;
          description = "Path to SSH private key";
        };

        timer = mkOption {
          type = types.str;
          default = "daily";
          description = "Systemd timer schedule (OnCalendar)";
        };

        environmentFile = mkOption {
          type = types.path;
          description = "File containing secrets (env vars). Should include RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS credentials, and optionally HEALTHCHECK_URL.";
        };

        repositoryFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to file containing restic repository URL. If null, RESTIC_REPOSITORY must be set in environmentFile.";
        };

        exclude = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Paths to exclude from backup";
        };

        pruneOpts = mkOption {
          type = types.listOf types.str;
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

        extraOptions = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Extra options to pass to restic";
        };
      };
    };
in
{
  options.services.restic-remote = {
    enable = mkEnableOption "restic-remote backup service";

    instances = mkOption {
      type = types.attrsOf (types.submodule instanceOptions);
      default = { };
      description = "Backup instances";
    };
  };

  config = mkIf cfg.enable {
    # Secrets configuration
    sops.secrets = lib.mkMerge (
      mapAttrsToList (name: instance: {
        "restic-remote/${name}/env" = {
          inherit (config.custom) sopsFile;
        };
        "restic-remote/${name}/sshkey" = {
          inherit (config.custom) sopsFile;
        };
      }) cfg.instances
    );

    fileSystems = lib.mkMerge (
      mapAttrsToList (name: instance: {
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
            "StrictHostKeyChecking=no"
            "UserKnownHostsFile=/dev/null"
            "ServerAliveInterval=10"
            "BatchMode=yes"
            "PasswordAuthentication=no"
          ];
        };
      }) cfg.instances
    );

    environment.systemPackages = [
      pkgs.restic
      pkgs.sshfs
    ];

    services.restic.backups = mapAttrs' (
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
      nameValuePair name (
        {
          inherit (instance)
            pruneOpts
            extraOptions
            environmentFile
            ;
          paths = backupPaths;
          exclude = excludePaths;
        }
        // lib.optionalAttrs (instance.repositoryFile != null) {
          inherit (instance) repositoryFile;
        }
      )
      // {

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
            if mountpoint -q ${mountDir}; then
              echo "Mount ${mountDir} is ready"
              break
            fi
            echo "Waiting for mount ${mountDir}... ($i/30)"
            # Trigger automount by accessing the directory
            ls ${mountDir} > /dev/null 2>&1 || true
            sleep 2
          done

          if ! mountpoint -q ${mountDir}; then
            echo "ERROR: Mount ${mountDir} is not available after 60 seconds"
            ${healthcheckScript "/fail"}
            exit 1
          fi

          ${healthcheckScript "/start"}
        '';

        backupCleanupCommand = healthcheckScript "";
      }
    ) cfg.instances;

    # Override the systemd service to add failure handling and create failure notification services
    systemd.services = mkMerge [
      (mapAttrs' (
        name: instance:
        nameValuePair "restic-backups-${name}" {
          serviceConfig = {
            TimeoutStartSec = "4h";
          };
          onFailure = [ "restic-backups-${name}-failure.service" ];
        }
      ) cfg.instances)
      (mkMerge (
        mapAttrsToList (name: instance: {
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
