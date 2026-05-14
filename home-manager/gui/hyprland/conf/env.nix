{ lib, ... }:
let
  mkEnv = name: value: {
    _args = [
      name
      value
    ];
  };
in
{
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      env = [
        # https://wiki.archlinux.org/title/Firefox/Tweaks#:~:text=MOZ%5FUSE%5FXINPUT2%3D1
        (mkEnv "MOZ_USE_XINPUT2" "1")
        (mkEnv "QT_QPA_PLATFORM" "wayland;xcb")
        (mkEnv "SDL_VIDEODRIVER" "wayland")
        (mkEnv "CLUTTER_BACKEND" "wayland")
        (mkEnv "XDG_CURRENT_DESKTOP" "Hyprland")
        (mkEnv "XDG_SESSION_TYPE" "wayland")
        (mkEnv "XDG_SESSION_DESKTOP" "Hyprland")
        (mkEnv "TERMINAL" "kitty")
      ];
    }
  ];
}
