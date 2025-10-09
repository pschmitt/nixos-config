{ ... }:

{
  # TODO put this in home-manager/gui/soundboard.nix
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
}
