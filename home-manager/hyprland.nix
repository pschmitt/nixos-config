{
  lib,
  osConfig ? null,
  ...
}:
let
  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
in
{
  imports = [
    ./hyprdynamicmonitor.nix
  ];

  xdg.configFile = {
    "hypr/config.d/nixos.conf" = {
      text = ''
        # Managed by Home Manager (home-manager/hyprland.nix)
        # Ensure hyprland.conf sources this file:
        #   source = $config_dir/nixos.conf
        #
        # Include the HyprDynamicMonitors output so Hyprland uses the generated layout.
        source = $config_dir/91-hdm-monitors.conf
      ''
      + lib.optionalString (hostName != null) ''
        source = $config_dir/hosts/${hostName}.conf
      '';
    };

    "hypr/config.d/plugins/hyprgrass.conf" = {
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
  // lib.optionalAttrs (hostName != null) {
    "hypr/config.d/hosts/${hostName}.conf" = {
      text =
          if hostName == "gk4" then
            ''
              device {
                # Internal laptop keyboard
                name = hailuck-co.-ltd-usb-keyboard
                kb_layout = us,de
              }

              input {
                # name = nvtk0603:00-0603:f001
                touchdevice {
                  enabled = true
                  output = "eDP-1"
                  transform = 3
                }
              }
            ''
        else
          ''
            # Host-specific Hypr overrides for ${hostName}
            # (currently unused)
          '';
    };
  };
}
