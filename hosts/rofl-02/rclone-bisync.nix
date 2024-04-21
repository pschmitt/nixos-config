{ lib, pkgs, ... }:

{
  systemd.services.rclone-bisync = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /mnt/data/srv/rclone/bin/rclone-bisync.sh";
      Environment = "PATH=${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.docker ]}";
    };
  };

  systemd.services.rclone-bisync-resync = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /mnt/data/srv/rclone/bin/rclone-bisync.sh --resync";
      Environment = "PATH=${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.docker ]}";
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
