{ lib, ... }:
let
  mkHhkbDevice = name: {
    inherit name;
    kb_layout = "de_hhkb";
  };
in
{
  # Mirrors ~/.config/hypr/config.d/input.conf (device + gesture tuning).
  # Docs: https://wiki.hyprland.org/Configuring/Variables/#input.
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      # Device-specific overrides from input.conf.
      device = [
        # HHKB (USB variants).
        (mkHhkbDevice "pfu-limited-hhkb-hybrid")
        (mkHhkbDevice "pfu-limited-hhkb-hybrid-keyboard")
        (mkHhkbDevice "pfu-limited-hhkb-hybrid-consumer-control")
        # HHKB over Bluetooth (multiple slots).
        (mkHhkbDevice "hhkb-hybrid_1-keyboard")
        (mkHhkbDevice "hhkb-hybrid_2-keyboard")
        (mkHhkbDevice "hhkb-hybrid_3-keyboard")
        (mkHhkbDevice "hhkb-hybrid_4-keyboard")
        # Magic Trackpad tuning.
        {
          name = "apple-inc.-magic-trackpad-usb-c";
          sensitivity = 0.3;
          accel_profile = "adaptive";
          scroll_factor = 1.8;
        }
      ];

      input = {
        kb_layout = "de,us";
        kb_variant = "";
        kb_model = "";
        kb_options = "";
        kb_rules = "";
        follow_mouse = 2;
        sensitivity = 0;
        touchpad.natural_scroll = false;
      };

      # Global gesture bindings from input.conf.
      gesture = lib.mkAfter [
        "3, horizontal, workspace"
        "3, up, scale: 1.5, fullscreen"
        "3, down, scale: 1.5, fullscreen"
      ];
      "gestures:workspace_swipe_invert" = false;
    }
  ];
}
