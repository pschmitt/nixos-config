{ ... }:
{
  imports = [
    ./hyprdynamicmonitor.nix
  ];

  xdg.configFile."hypr/config.d/nixos.conf" = {
    text = ''
      # Managed by Home Manager (home-manager/hyprland.nix)
      # Ensure hyprland.conf sources this file:
      #   source = $config_dir/nixos.conf
      #
      # Include the HyprDynamicMonitors output so Hyprland uses the generated layout.
      source = $config_dir/91-hdm-monitors.conf
    '';
  };

  xdg.configFile."hypr/config.d/plugins/hyprgrass.conf" = {
    text = ''
      # Hyprgrass touch gesture tuning
      plugin {
        touch_gestures {
          sensitivity = 4.0
          workspace_swipe_fingers = 3
          workspace_swipe_edge = d
          long_press_delay = 400
          resize_on_border_long_press = true
          edge_margin = 10
          emulate_touchpad_swipe = true
        }
      }
    '';
  };
}
