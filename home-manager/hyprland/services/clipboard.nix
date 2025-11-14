{ lib, ... }:
{
  wayland.windowManager.hyprland.settings.exec = lib.mkAfter [
    "$ensure1 -j clipboard -- wl-clip-persist --clipboard both"
    "$ensure1 -j clipboard -- wl-paste --type text --watch cliphist store"
    "$ensure1 -j clipboard -- wl-paste --type image --watch cliphist store"
  ];
}
