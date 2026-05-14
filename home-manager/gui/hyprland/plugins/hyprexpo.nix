{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  luaBind = import ../lib/lua-bind.nix { inherit lib; };
in
{
  wayland.windowManager.hyprland.plugins = [
    pkgs.master.hyprlandPlugins.hyprexpo
    # inputs.hyprland-plugins.packages.${pkgs.system}.hyprexpo
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ (luaBind.mkBind "SUPER, g, hyprexpo:expo, toggle") ];
    config.plugin.hyprexpo = {
      columns = 3;
      gap_size = 5;
      skip_empty = true;
    };
  };
}
