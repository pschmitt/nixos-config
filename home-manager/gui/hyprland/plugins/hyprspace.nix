{
  lib,
  pkgs,
  ...
}:
let
  luaBind = import ../lib/lua-bind.nix { inherit lib; };
in
{
  wayland.windowManager.hyprland.plugins = [
    pkgs.hyprlandPlugins.hyprspace
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ (luaBind.mkBind "SUPER, g, overview:toggle, all") ];
    config.plugin.hyprspace = { };
  };
}
