{ pkgs, ... }:
{
  wayland.windowManager.hyprland.plugins = [
    pkgs.master.hyprlandPlugins.hyprtasking
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ "SUPER, g, hyprtasking:toggle, all" ];
    plugin.hyprtasking = {
      layout = "grid";
    };
  };
}
