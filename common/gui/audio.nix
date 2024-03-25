{ pkgs, ... }: {
  imports = [
    ./soundboard.nix
  ];

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  environment.systemPackages = with pkgs; [
    ncpamixer
    pamixer
    pavucontrol
    pulseaudio # pactl + pacmd

    # apps
    audacity
    (sox.override { enableLame = true; enableAMR = false; })

    # patching
    helvum
    qpwgraph
  ];
}
