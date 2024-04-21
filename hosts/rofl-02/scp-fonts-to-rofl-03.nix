{ pkgs, ... }: {
  systemd.services.scp-fonts-to-rofl-03 = {
    description = "SCP font files to github-actions@rofl-03.heimat.dev";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.openssh}/bin/scp \
          -i /etc/ssh/ssh_host_ed25519_key \
          -o UserKnownHostsFile=/dev/null \
          -o StrictHostKeyChecking=no \
          "$${SOURCE_DIR}/"* \
          "$${REMOTE_USER}@$${REMOTE_USER}:$${DEST_DIR}/"
      '';
      Environment = [
        "SOURCE_DIR=/mnt/data/srv/nextcloud/data/nextcloud/pschmitt/files/Fonts"
        "DEST_DIR=src"
        "REMOTE_USER=github-actions"
        "REMOTE_HOST=rofl-03.heimat.dev"
      ];
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
  systemd.timers.scp-fonts-to-rofl-03 = {
    description = "Timer for SCP to github-actions@rofl-03.heimat.dev";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true; # Ensures missed tasks are run on boot
    };
  };
}
