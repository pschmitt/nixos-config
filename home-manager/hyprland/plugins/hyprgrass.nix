{ inputs, lib, pkgs, ... }:
{
  wayland.windowManager.hyprland.plugins =
    lib.mkAfter [
      inputs.hyprgrass.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

  wayland.windowManager.hyprland.settings.plugin.touch_gestures =
    lib.mkMerge [
      (lib.mkDefault {
        sensitivity = 4.0;
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
          ", tap:4, killactive"
        ];
        hyprgrass-bindm = [
          ", longpress:2, movewindow"
        ];
      }
    ];
}
