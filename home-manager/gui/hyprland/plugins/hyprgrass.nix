{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  wayland.windowManager.hyprland.plugins = [
    # pkgs.hyprlandPlugins.hyprgrass
    inputs.hyprgrass.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  wayland.windowManager.hyprland.settings.plugin.touch_gestures = lib.mkMerge [
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
        ", edge:d:u, exec, $bin_dir/toggle-soft-keyboard.sh"
        ", swipe:4:d, killactive"
        ", swipe:4:u, exec, kitty"
        # FIXME
        # ", pinch:3:i, killactive"
        # ", pinch:3:o, exec, kitty"
      ];
      hyprgrass-bindm = [
        ", longpress:2, movewindow"
        ", longpress:3, resizewindow"
      ];
    }
  ];
}
