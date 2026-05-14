{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  binDir = "~/.config/hypr/bin";
in
{
  wayland.windowManager.hyprland.plugins = [
    inputs.hyprgrass.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  wayland.windowManager.hyprland.settings.config.plugin.touch_gestures = lib.mkMerge [
    (lib.mkDefault {
      sensitivity = 6.0;
      workspace_swipe_fingers = 3;
      workspace_swipe_edge = "d";
      long_press_delay = 400;
      resize_on_border_long_press = true;
      edge_margin = 10;
      emulate_touchpad_swipe = true;
    })
    {
      hyprgrass-bind = [
        ", edge:d:u, exec, ${binDir}/toggle-soft-keyboard.sh"
        ", swipe:4:d, killactive"
        ", swipe:4:u, exec, kitty"
      ];
      hyprgrass-bindm = [
        ", longpress:2, movewindow"
        ", longpress:3, resizewindow"
      ];
    }
  ];
}
