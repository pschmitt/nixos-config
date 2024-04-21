{ pkgs, ... }: {
  systemd.services.rsync-fonts-to-rofl-03 = {
    description = "Rsync font files to github-actions@rofl-03.heimat.dev";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      export PATH=${pkgs.openssh}/bin:$PATH
      exec ${pkgs.rsync}/bin/rsync -avz -e "ssh -i ''${IDENTITY_FILE} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" \
        "''${SOURCE_DIR}/" \
        "''${REMOTE_USER}@''${REMOTE_HOST}:''${DEST_DIR}/"
    '';
    serviceConfig = {
      Type = "simple";
      Environment = [
        "SOURCE_DIR=/mnt/data/srv/nextcloud/data/nextcloud/pschmitt/files/Fonts"
        "DEST_DIR=src"
        "REMOTE_USER=github-actions"
        "REMOTE_HOST=rofl-03.heimat.dev"
        "IDENTITY_FILE=/etc/ssh/ssh_host_ed25519_key"
      ];
      Restart = "on-failure";
      RestartSec = 30;
    };
  };

  systemd.timers.rsync-fonts-to-rofl-03 = {
    description = "Timer for SCP to github-actions@rofl-03.heimat.dev";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true; # Ensures missed tasks are run on boot
    };
  };
}
