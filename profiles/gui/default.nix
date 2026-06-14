{
  imports = [
    # system
    ./audio.nix
    ./bluetooth.nix
    ./gpu.nix
    ./linger.nix

    # misc
    ./apps.nix
    ./browser.nix
    ./fonts.nix
    ./theme.nix

    # services
    ./flatpak.nix
    ./gnome-keyring.nix
    ./libvirt.nix
    ./services.nix
    ./snapper.nix
    ./v4l2loopback.nix

    # io
    ./keyboard.nix
    ./logitech-mouse.nix
    ./printers.nix
    ./touchpad.nix
  ];

  # Display managers and desktop environments are opt-in roles — see
  # profiles/display-manager-*.nix and profiles/desktop-*.nix. Hosts compose the
  # ones they actually run (e.g. the workstation profile picks hyprland + gnome
  # + gdm).
}

# vim: set ft=nix et ts=2 sw=2 :
