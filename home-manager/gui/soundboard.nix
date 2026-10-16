{ config, pkgs, ... }:
let
  serviceName = "soundboard-tagesschau";
  restartAudio = ''
    run ${pkgs.systemd}/bin/systemctl --user try-restart pipewire.service pipewire-pulse.service wireplumber.service
  '';
in
{
  home.packages = [ pkgs.soundboard ];

  # "Meeting Microphone": a virtual source that the denoised microphone and
  # soundboard clips are linked into by the WirePlumber script below.
  xdg.configFile."pipewire/pipewire.conf.d/99-soundboard.conf" = {
    onChange = restartAudio;
    text = builtins.toJSON {
      "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "media.class" = "Audio/Source/Virtual";
            "node.name" = "meeting_source";
            "node.description" = "Meeting Microphone";
            "audio.position" = [
              "FL"
              "FR"
            ];
            "priority.session" = 2500;
            "adapter.auto-port-config" = {
              mode = "dsp";
              monitor = false;
              position = "preserve";
            };
          };
        }
      ];
    };
  };

  xdg.configFile."wireplumber/wireplumber.conf.d/90-meeting-mic.conf" = {
    onChange = restartAudio;
    text = builtins.toJSON {
      "wireplumber.components" = [
        {
          name = "${./wireplumber/meeting-mic.lua}";
          type = "script/lua";
          provides = "custom.meeting-mic";
        }
      ];
      "wireplumber.profiles".main."custom.meeting-mic" = "required";
    };
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
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.ms-teams}/bin/ms-teams in-a-meeting && ${pkgs.soundboard}/bin/soundboard play tagesschau || echo not in meeting >&2'";
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
