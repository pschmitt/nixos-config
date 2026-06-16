{
  config,
  lib,
  pkgs,
  ...
}:

let
  rcloneConfig = config.sops.secrets."rclone/config".path;
  rcloneBisyncDocuments = pkgs.writeShellApplication {
    name = "rclone-bisync-documents";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.procps
      pkgs.rclone
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/rclone-bisync-documents.sh;
  };

  bisyncCmd =
    extraArgs:
    lib.concatStringsSep " " (
      [
        "${rcloneBisyncDocuments}/bin/rclone-bisync-documents"
        "--config"
        (lib.escapeShellArg rcloneConfig)
      ]
      ++ extraArgs
    );
in
{
  sops.secrets."rclone/config" = config.custom.mkSecret {
    mode = "0600";
  };

  systemd = {
    services = {
      rclone-bisync-documents = {
        description = "Rclone bisync - Documents sync";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "rclone";
          CacheDirectory = "rclone";
          TimeoutStartSec = "3h";
          User = "root";
        };

        script = bisyncCmd [ ];
      };

      rclone-bisync-documents-resync = {
        description = "Rclone bisync - Documents full resync";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "rclone";
          CacheDirectory = "rclone";
          TimeoutStartSec = "3h";
          User = "root";
        };

        script = bisyncCmd [ "--resync" ];
      };
    };

    timers = {
      rclone-bisync-documents = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          RandomizedDelaySec = "600"; # 10min
          Persistent = true;
        };
      };

      rclone-bisync-documents-resync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "05:45:00";
          Persistent = true;
        };
      };
    };
  };
}
