{ lib, pkgs, ... }:
{
  systemd.services.podsync-yt-dlp-update = {
    description = "Update yt-dlp (youtube-dl) in podsync container";
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/srv/podsync";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose exec podsync youtube-dl -U";
    };
  };

  systemd.timers.podsync-yt-dlp-update = {
    description = "Daily timer for podsync youtube-dl update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check program "podsync-yt-dlp-update.timer" with path "${pkgs.systemd}/bin/systemctl is-active podsync-yt-dlp-update.timer"
      group services
      if status > 0 then alert
  '';
}
