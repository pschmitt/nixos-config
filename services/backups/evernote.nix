{ pkgs, ... }:
{
  systemd.services.evernote-backup = {
    description = "Evernote Backup Service";
    path = with pkgs; [
      bash
      coreutils
      docker
    ];
    script = ''
      /srv/evernote-backup/bin/evernote-backup-all.sh
    '';
  };

  systemd.timers.evernote-backup = {
    description = "Daily Evernote Backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "600"; # 10min
      Persistent = true;
    };
  };
}
