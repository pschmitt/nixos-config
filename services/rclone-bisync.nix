{
  config,
  pkgs,
  ...
}:

let
  rcloneConfig = config.sops.secrets."rclone/config".path;

  bisyncCmd = extraArgs: ''
    ${pkgs.rclone}/bin/rclone bisync "nextcloud:Documents" "drive:Documents" \
      --config ${rcloneConfig} \
      --check-access \
      --check-filename .rclone-test.empty \
      --recover \
      --remove-empty-dirs \
      --workdir /var/cache/rclone/bisync \
      --verbose \
      ${extraArgs}
  '';
in
{
  sops.secrets."rclone/config" = {
    inherit (config.custom) sopsFile;
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
          User = "root";
        };

        script = bisyncCmd "";
      };

      rclone-bisync-documents-resync = {
        description = "Rclone bisync - Documents full resync";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "rclone";
          CacheDirectory = "rclone";
          User = "root";
        };

        script = bisyncCmd "--resync";
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
          OnCalendar = "05:00:00";
          RandomizedDelaySec = "3600";
          Persistent = true;
        };
      };
    };
  };
}
