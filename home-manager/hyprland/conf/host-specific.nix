{
  osConfig ? null,
  ...
}:
{
  wayland.windowManager.hyprland.settings =
    let
      hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
    in
    if hostName == "gk4" then
      {
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
      }
    else
      { };
}
