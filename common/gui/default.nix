{
  imports = [
    ./apps.nix
    ./audio.nix
    ./browser.nix
    ./bluetooth.nix
    ./fonts.nix
    ./gnome-keyring.nix
    ./gpu.nix
    ./go-hass-agent.nix
    ./hacompanion.nix
    ./flatpak.nix
    ./keyboard.nix
    ./libvirt.nix
    ./logitech-mouse.nix
    ./printer.nix
    ./services.nix
    ./snapper.nix
    ./touchpad.nix
    ./theme.nix
    ./v4l2loopback.nix

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
