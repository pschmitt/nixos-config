{
  pkgs,
  ...
}:
{
  wayland.windowManager.hyprland.plugins = [
    pkgs.master.hyprlandPlugins.hyprspace
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ "SUPER, g, overview:toggle, all" ];
    plugin.hyprspace = { };
  };
}
