# workstation — interactive desktop/laptop hosts (ge2, gk4, x13): the shared
# GUI + laptop + work base every personal machine runs.
{ config, ... }:
{
  imports = [
    ./global
    ./gui

    # Desktop + display manager (opt-in roles); these laptops run Hyprland and
    # GNOME under GDM.
    ./desktop-hyprland.nix
    ./desktop-gnome.nix
    ./display-manager-gdm.nix

    ./laptop

    # Role features (opt-in) currently run by all three laptops.
    ./vpn-mullvad.nix
    ./privacy-tor.nix
    ./net-debug.nix
    ./nrf-dev.nix
    ./android-waydroid.nix
    ./work-wiit.nix

    ../services/restic
  ];

  home-manager.users.${config.mainUser.username}.services.go-hass-agent.enableWorkstationCommands =
    true;
}
