let
  mkHhkb = name: {
    inherit name;
    kb_layout = "hhkb-de,de,us";
  };
in
{
  # Input devices, keyboard layout and touchpad gestures.
  # Docs: https://wiki.hypr.land/Configuring/Variables/#input
  wayland.windowManager.hyprland.settings = {
    # Per-device overrides -> hl.device({ ... }).
    device = [
      # HHKB USB variants.
      (mkHhkb "pfu-limited-hhkb-hybrid")
      (mkHhkb "pfu-limited-hhkb-hybrid-keyboard")
      (mkHhkb "pfu-limited-hhkb-hybrid-consumer-control")
      # HHKB over Bluetooth (multiple slots).
      (mkHhkb "hhkb-hybrid_1-keyboard")
      (mkHhkb "hhkb-hybrid_2-keyboard")
      (mkHhkb "hhkb-hybrid_3-keyboard")
      (mkHhkb "hhkb-hybrid_4-keyboard")

      # Magic Trackpad tuning.
      {
        name = "apple-inc.-magic-trackpad-usb-c";
        sensitivity = 0.3;
        accel_profile = "adaptive";
        scroll_factor = 1.8;
      }

      # GPD Pocket 4 keyboard and touchpad.
      # NOTE: relevant even on other hosts because of the KVM module.
      {
        name = "hailuck-co.-ltd-usb-keyboard";
        kb_layout = "gpdpocket4-de,gpdpocket4-us,us,de";
      }
      {
        # Inverted scrolling for the built-in touchpad.
        name = "hailuck-co.-ltd-usb-keyboard-mouse";
        natural_scroll = true;
      }
    ];

    config = {
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
      gestures.workspace_swipe_invert = false;
    };

    # Touchpad gestures (core Hyprland; touchscreen gestures live in hyprgrass).
    gesture = [
      {
        fingers = 3;
        direction = "horizontal";
        action = "workspace";
      }
      {
        fingers = 3;
        direction = "up";
        scale = 1.5;
        action = "fullscreen";
      }
      {
        fingers = 3;
        direction = "down";
        scale = 1.5;
        action = "fullscreen";
      }
    ];
  };
}
