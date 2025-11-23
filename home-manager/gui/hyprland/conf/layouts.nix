{
  # Mirrors ~/.config/hypr/config.d/layouts.conf.
  # Docs: https://wiki.hyprland.org/Configuring/Dwindle-Layout/ and /Master-Layout/.
  wayland.windowManager.hyprland.settings = {
    # Layout tweaks from layouts.conf.
    dwindle = {
      pseudotile = true;
      preserve_split = true;
      smart_split = true;
    };

    master = {
      new_on_top = true;
    };
  };
}
