{ config, ... }:

{
  services.pipewire.extraConfig.pipewire."99-soundboard" = {
    context.objects = [
      {
        factory = "adapter";
        args = {
          factory.name = "support.null-audio-sink";
          media.class = "Audio/Sink";
          node.name = "soundboard-sink";
          node.description = "Soundboard Sink";
          adapter.auto-port-config = {
            mode = "dsp";
            monitor = true;
            position = "preserve";
          };
        };
      }
    ];
  };

  systemd.user.services.soundboard-tagesschau = {
    description = "Play Tagesschau Jingle";
    documentation = [
      "file://${config.custom.homeDirectory}/.config/zsh/plugins/local/soundboard.zsh"
    ];
    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];

    serviceConfig = {
      # FIXME Ideally we would determine if we are currently attending the
      # Daily Meeting but MSTeams isn't giving out too much information via
      # the URL/title of the meeting...
      ExecStart = "${config.custom.homeDirectory}/bin/zhj 'ms-teams::in-a-meeting && soundboard::play tagesschau || echo not in zoom >&2'";
    };

    wantedBy = [ "default.target" ];
  };

  systemd.user.timers.soundboard-tagesschau = {
    enable = true;
    description = "Play Tagesschau Jingle at 10:00 AM";

    timerConfig = {
      OnCalendar = "10:00";
      Persistent = true;
    };

    wantedBy = [ "default.target" ];
  };
}
