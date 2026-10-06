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

  rcloneBisyncIncoming = pkgs.writeShellApplication {
    name = "rclone-bisync-incoming";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.rclone
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/rclone-bisync-incoming.sh;
  };

  bisyncCmd =
    package: extraArgs:
    lib.concatStringsSep " " (
      [
        "${package}/bin/${package.name}"
        "--config"
        (lib.escapeShellArg rcloneConfig)
      ]
      ++ extraArgs
    );
in
{
  sops.secrets."rclone/config" = config.sops.mkHostSecret {
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

        script = bisyncCmd rcloneBisyncDocuments [ ];
      };

      rclone-bisync-incoming = {
        description = "Rclone bisync - Documents/Incoming (scanner inbox)";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "rclone";
          CacheDirectory = "rclone";
          TimeoutStartSec = "30min";
          User = "root";
        };

        script = bisyncCmd rcloneBisyncIncoming [ ];
      };

      rclone-bisync-incoming-resync = {
        description = "Rclone bisync - Documents/Incoming full resync";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "rclone";
          CacheDirectory = "rclone";
          TimeoutStartSec = "30min";
          User = "root";
        };

        script = bisyncCmd rcloneBisyncIncoming [ "--resync" ];
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

        script = bisyncCmd rcloneBisyncDocuments [ "--resync" ];
      };
    };

    timers = {
      rclone-bisync-incoming = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "1min";
          AccuracySec = "5s";
        };
      };

      rclone-bisync-documents = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          RandomizedDelaySec = "600"; # 10min
          Persistent = true;
        };
      };
    };
  };
}
