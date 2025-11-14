{ lib, ... }:
{
  wayland.windowManager.hyprland.settings.exec = lib.mkAfter [
    "$ensure1 -j hints -- hintsd"
  ];
}
