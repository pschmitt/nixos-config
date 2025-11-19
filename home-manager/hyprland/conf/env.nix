{ lib, ... }:
{
  # Mirrors ~/.config/hypr/config.d/env.conf (Wayland env overrides).
  # See https://wiki.hyprland.org/Configuring/Environment-variables/ for reference.
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      # Propagate the graphical session environment to systemd/DBus.
      "exec-once" = [
        "dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP"
      ];

      # Toolkit/env overrides from env.conf.
      env = [
        # "MOZ_ENABLE_WAYLAND,1"
        # https://wiki.archlinux.org/title/Firefox/Tweaks#:~:text=MOZ%5FUSE%5FXINPUT2%3D1
        "MOZ_USE_XINPUT2,1"

        # Force Wayland (with xcb fallback) for Qt apps.
        "QT_QPA_PLATFORM,wayland;xcb"

        # SDL + Clutter should default to Wayland.
        "SDL_VIDEODRIVER,wayland"
        "CLUTTER_BACKEND,wayland"

        # Identify the Hyprland desktop/session.
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
      ];

      # Optional overrides kept from env.conf for future toggling:
      #   env = MOZ_ENABLE_WAYLAND,1
      #   env = XCURSOR_THEME,Bibata-Modern-Ice
      #   env = XCURSOR_SIZE,24
      #   env = GTK_THEME,Colloid-nord-dark
      #   env = QT_QPA_PLATFORMTHEME,qt5ct
    }
  ];
}
