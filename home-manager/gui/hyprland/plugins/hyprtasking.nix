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
    inputs.hyprtasking.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ (luaBind.mkBind "SUPER, g, hyprtasking:toggle, all") ];
    config.plugin.hyprtasking = {
      layout = "grid";
    };
  };
}
