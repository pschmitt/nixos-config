{ pkgs, ... }:

{
  systemd.services.rclone-bisync = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /mnt/data/srv/rclone/bin/rclone-bisync.sh";
    };
  };

  systemd.services.rclone-bisync-resync = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /mnt/data/srv/rclone/bin/rclone-bisync.sh --resync";
    };
  };

  systemd.timers.rclone-bisync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "600"; # 10min
      Persistent = true;
    };
  };

  systemd.timers.rclone-bisync-resync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "05:00:00";
      RandomizedDelaySec = "3600";
      Persistent = true;
    };
  };
}

