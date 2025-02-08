{ pkgs, ... }:
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
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
