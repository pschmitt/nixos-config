{
  pkgs,
  ...
}:
{
  wayland.windowManager.hyprland.plugins = [
    pkgs.hyprlandPlugins.hyprexpo
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ "SUPER, g, hyprexpo:expo, toggle" ];
    plugin.hyprexpo = {
      columns = 3;
      gap_size = 5;
      skip_empty = true;
    };
  };
}
