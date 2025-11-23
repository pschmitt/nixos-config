{
  pkgs,
  ...
}:
{
  wayland.windowManager.hyprland.plugins = [
    pkgs.hyprlandPlugins.hyprspace
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ "SUPER, g, overview:toggle, all" ];
    plugin.hyprspace = { };
  };
}
