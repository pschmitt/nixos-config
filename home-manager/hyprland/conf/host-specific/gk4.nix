{
  wayland.windowManager.hyprland.settings = {
    device = [
      {
        name = "hailuck-co.-ltd-usb-keyboard";
        kb_layout = "gpdpocket4,us,de";
      }
      {
        # Enable inverted scrolling for the built-in touchpad.
        name = "hailuck-co.-ltd-usb-keyboard-mouse";
        natural_scroll = true;
      }
    ];

    input.touchdevice = {
      enabled = true;
      output = "eDP-1";
      transform = 3;
    };
  };
}
