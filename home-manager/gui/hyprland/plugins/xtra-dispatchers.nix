{ pkgs, ... }:
{
  wayland.windowManager.hyprland.plugins = with pkgs.master.hyprlandPlugins; [
    xtra-dispatchers
  ];
}
