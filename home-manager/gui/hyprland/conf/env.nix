{ config, ... }:
let
  # custom.desktop.theme.sessionVariables (modules/theme.nix) is also applied
  # as home.sessionVariables, but that only reaches login shells
  # (~/.profile). uwsm starts Hyprland with its own curated environment, so
  # anything Hyprland forks directly (keybinds, waybar on-click, exec-once)
  # never sees them unless Hyprland exports them itself here. Apps launched
  # from a terminal look fine only because the login shell re-sources
  # hm-session-vars.sh.
  sessionVars = config.custom.desktop.theme.sessionVariables;
in
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

  ]
  # Re-export the GTK/Qt theming vars into Hyprland's own process
  # environment so every process it forks directly (keybinds, waybar
  # on-click handlers, exec-once) inherits them too, not just login
  # shells. See comment above.
  ++ (map (name: {
    _args = [
      name
      sessionVars.${name}
    ];
  }) (builtins.attrNames sessionVars));

  # Optional overrides kept for future toggling:
  #   { _args = [ "MOZ_ENABLE_WAYLAND" "1" ]; }
}
