{ pkgs, ... }: {
  systemd.services.scp-fonts-to-rolf-03 = {
    description = "SCP files to github-actions@rofl-03.heimat.dev";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.openssh}/bin/scp -i /etc/ssh/ssh_host_ed25519_key '$SOURCE_DIR/'* 'github-actions@rofl-03.heimat.dev:$DEST_DIR/";
      Environment = [
        "SOURCE_DIR=/mnt/data/srv/nextcloud/data/nextcloud/pschmitt/files/Fonts"
        "DEST_DIR=src"
      ];
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
  systemd.timers.scp-fonts-to-rolf-03 = {
    description = "Timer for SCP to github-actions@rofl-03.heimat.dev";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly:0/2"; # Every 2 hours
      Persistent = true; # Ensures missed tasks are run on boot
    };
  };
}
