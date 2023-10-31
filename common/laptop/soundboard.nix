{ config, pkgs, ... }:

{
  systemd.user.services.soundboard-tagesschau = {
    description = "Play Tagesschau Jingle";
    documentation = [ "file://${config.custom.homeDirectory}/.config/zsh/plugins/local/soundboard.zsh" ];
    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];

    serviceConfig = {
      ExecStart = "${config.custom.homeDirectory}/bin/zhj 'zoom::in-home-room && soundboard::play tagesschau || echo not in zoom >&2'";
    };

    wantedBy = [ "default.target" ];
  };

  systemd.user.timers.soundboard-tagesschau-timer = {
    enable = true;
    description = "Play Tagesschau Jingle at 10:00 AM";

    timerConfig = {
      OnCalendar = "10:00";
      Persistent = true;
    };

    wantedBy = [ "default.target" ];
  };
}
