_: {
  xdg.configFile."hypr/lua/env.lua".text = ''
    -- Propagate graphical session to systemd/DBus on startup.
    -- (dbus-update-activation-environment lives in autostart.lua)

    -- https://wiki.archlinux.org/title/Firefox/Tweaks#MOZ_USE_XINPUT2
    hl.env("MOZ_USE_XINPUT2", "1")

    -- Force Wayland (with xcb fallback) for Qt apps.
    hl.env("QT_QPA_PLATFORM", "wayland;xcb")

    -- SDL + Clutter default to Wayland.
    hl.env("SDL_VIDEODRIVER", "wayland")
    hl.env("CLUTTER_BACKEND", "wayland")

    -- Hyprland desktop identity.
    hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
    hl.env("XDG_SESSION_TYPE",    "wayland")
    hl.env("XDG_SESSION_DESKTOP", "Hyprland")

    -- Preferred terminal for xdg-terminal-exec / autostart helpers.
    hl.env("TERMINAL", "kitty")

    -- Optional (commented out to match env.conf):
    -- hl.env("MOZ_ENABLE_WAYLAND", "1")
    -- hl.env("GTK_THEME",          "Colloid-nord-dark")
    -- hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
  '';
}
