{
  # Wayland/toolkit environment overrides -> hl.env("KEY", "value").
  # Docs: https://wiki.hypr.land/Configuring/Environment-variables/
  # (dbus-update-activation-environment lives in autostart.)
  wayland.windowManager.hyprland.settings.env = [
    # https://wiki.archlinux.org/title/Firefox/Tweaks#MOZ_USE_XINPUT2
    {
      _args = [
        "MOZ_USE_XINPUT2"
        "1"
      ];
    }

    # Force Wayland (with xcb fallback) for Qt apps.
    {
      _args = [
        "QT_QPA_PLATFORM"
        "wayland;xcb"
      ];
    }

    # SDL + Clutter default to Wayland.
    {
      _args = [
        "SDL_VIDEODRIVER"
        "wayland"
      ];
    }
    {
      _args = [
        "CLUTTER_BACKEND"
        "wayland"
      ];
    }

    # Hyprland desktop identity.
    {
      _args = [
        "XDG_CURRENT_DESKTOP"
        "Hyprland"
      ];
    }
    {
      _args = [
        "XDG_SESSION_TYPE"
        "wayland"
      ];
    }
    {
      _args = [
        "XDG_SESSION_DESKTOP"
        "Hyprland"
      ];
    }

    # Preferred terminal for xdg-terminal-exec / autostart helpers.
    {
      _args = [
        "TERMINAL"
        "kitty"
      ];
    }

    # Optional overrides kept for future toggling:
    #   { _args = [ "MOZ_ENABLE_WAYLAND" "1" ]; }
    #   { _args = [ "GTK_THEME" "Colloid-nord-dark" ]; }
    #   { _args = [ "QT_QPA_PLATFORMTHEME" "qt5ct" ]; }
  ];
}
