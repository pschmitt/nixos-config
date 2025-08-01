{ pkgs, ... }:
{
  imports = [ ./soundboard.nix ];

  # Enable sound with pipewire.
  # https://nixos.wiki/wiki/PipeWire
  # TODO as of 04.01.2025: hardware.pulseaudio -> services.pulseaudio
  # default value: false
  # services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    # jack.enable = true;
  };

  environment.systemPackages = with pkgs; [
    ncpamixer
    pamixer
    pavucontrol
    pulseaudio # pactl + pacmd

    # apps
    master.audacity # XXX https://nixpk.gs/pr-tracker.html?pr=429334
    (sox.override {
      enableLame = true;
      enableAMR = false;
    })

    # patching
    helvum
    qpwgraph
  ];
}
