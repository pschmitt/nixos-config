{
  imports = [
    # system
    ./audio.nix
    ./bluetooth.nix
    ./gpu.nix

    # misc
    ./apps.nix
    ./browser.nix
    ./fonts.nix
    ./theme.nix

    # services
    ./flatpak.nix
    ./gnome-keyring.nix
    ./go-hass-agent.nix
    # ./hacompanion.nix
    ./libvirt.nix
    ./services.nix
    ./snapper.nix
    ./v4l2loopback.nix

    # io
    ./keyboard.nix
    ./logitech-mouse.nix
    ./printers.nix
    ./touchpad.nix

    # Display Manager
    ./gdm.nix
    # ./greetd.nix

    # Desktops
    ./gnome.nix
    ./hyprland.nix
    ./niri.nix
    ./sway.nix
  ];

}

# vim: set ft=nix et ts=2 sw=2 :
