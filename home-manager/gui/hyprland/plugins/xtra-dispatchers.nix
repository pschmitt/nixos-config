{ inputs, pkgs, ... }:
{
  wayland.windowManager.hyprland.plugins = [
    # pkgs.master.hyprlandPlugins.xtra-dispatchers
    inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.xtra-dispatchers
  ];
}
