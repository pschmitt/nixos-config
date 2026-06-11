# workstation — interactive desktop/laptop hosts (ge2, gk4, x13): the shared
# GUI + laptop + work base every personal machine runs.
{
  imports = [
    ../common/global
    ../common/gui

    # Desktop + display manager (opt-in roles); these laptops run Hyprland and
    # GNOME under GDM.
    ./desktop-hyprland.nix
    ./desktop-gnome.nix
    ./display-manager-gdm.nix

    ../common/laptop
    ../common/work
    ../services/restic
  ];
}
