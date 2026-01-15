{ config, ... }:
let
  serviceName = "soundboard-tagesschau";
in
{

  xdg.configFile."pipewire/pipewire.conf.d/99-soundboard.conf".text = builtins.toJSON {
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "media.class" = "Audio/Sink";
          "node.name" = "soundboard-sink";
          "node.description" = "Soundboard Sink";
          "adapter.auto-port-config" = {
            mode = "dsp";
            monitor = true;
            position = "preserve";
          };
        };
      }
    ];
  };

  systemd.user.services.${serviceName} = {
    Unit = {
      Description = "Play Tagesschau Jingle";
      Documentation = [
        "file://${config.home.homeDirectory}/.config/zsh/plugins/local/soundboard.zsh"
      ];
    };

    Service = {
      # FIXME Ideally we would determine if we are currently attending the
      # Daily Meeting but MSTeams isn't giving out too much information via
      # the URL/title of the meeting...
      ExecStart = "${config.home.homeDirectory}/bin/zhj 'ms-teams::in-a-meeting && soundboard::play tagesschau || echo not in meeting >&2'";
    };
  };

  systemd.user.timers.${serviceName} = {
    Unit = {
      Description = "Play Tagesschau Jingle at 09:30 AM";
    };

    Timer = {
      OnCalendar = "09:30";
      Persistent = true;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
