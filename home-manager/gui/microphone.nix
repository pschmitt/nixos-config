{ pkgs, ... }:
{
  # Home Manager can update the graph after PipeWire has already started.
  xdg.configFile."pipewire/pipewire.conf.d/90-microphone.conf".onChange = ''
    run ${pkgs.systemd}/bin/systemctl --user try-restart pipewire.service pipewire-pulse.service wireplumber.service
  '';

  # Restrict the denoiser to physical microphones, never the combined source.
  xdg.configFile."pipewire/pipewire.conf.d/90-microphone.conf".text = builtins.toJSON {
    "context.modules" = [
      {
        name = "libpipewire-module-filter-chain";
        args = {
          "node.description" = "Microphone (RNNoise)";
          "audio.rate" = 48000;
          "audio.position" = [ "MONO" ];
          "filter.graph".nodes = [
            {
              type = "ladspa";
              name = "rnnoise";
              plugin = "${pkgs.rnnoise-plugin}/lib/ladspa/librnnoise_ladspa.so";
              label = "noise_suppressor_mono";
              control = {
                "VAD Threshold (%)" = 50.0;
                "VAD Grace Period (ms)" = 200;
                "Retroactive VAD Grace (ms)" = 0;
              };
            }
          ];
          "capture.props" = {
            "node.name" = "capture.rnnoise_source";
            "node.passive" = true;
          };
          "playback.props" = {
            "node.name" = "rnnoise_source";
            "media.class" = "Audio/Source";
            "filter.smart" = true;
            "filter.smart.name" = "rnnoise";
            "filter.smart.targetable" = true;
            "filter.smart.target" = {
              "media.class" = "Audio/Source";
              "device.api" = "alsa";
            };
          };
        };
      }
    ];
  };
}
