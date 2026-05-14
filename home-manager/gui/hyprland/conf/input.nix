{ lib, ... }:
let
  mkHhkbDevice = name: {
    inherit name;
    kb_layout = "hhkb-de,de,us";
  };
in
{
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
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

        gestures = {
          workspace_swipe_invert = false;
        };
      };

      device = [
        (mkHhkbDevice "pfu-limited-hhkb-hybrid")
        (mkHhkbDevice "pfu-limited-hhkb-hybrid-keyboard")
        (mkHhkbDevice "pfu-limited-hhkb-hybrid-consumer-control")
        (mkHhkbDevice "hhkb-hybrid_1-keyboard")
        (mkHhkbDevice "hhkb-hybrid_2-keyboard")
        (mkHhkbDevice "hhkb-hybrid_3-keyboard")
        (mkHhkbDevice "hhkb-hybrid_4-keyboard")
        {
          name = "apple-inc.-magic-trackpad-usb-c";
          sensitivity = 0.3;
          accel_profile = "adaptive";
          scroll_factor = 1.8;
        }
        # NOTE These are relevant even on other hosts because of the KVM module!
        {
          name = "hailuck-co.-ltd-usb-keyboard";
          kb_layout = "gpdpocket4-de,gpdpocket4-us,us,de";
        }
        {
          name = "hailuck-co.-ltd-usb-keyboard-mouse";
          natural_scroll = true;
        }
      ];

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
    }
  ];
}
