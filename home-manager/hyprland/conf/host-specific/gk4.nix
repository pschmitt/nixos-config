{ lib, ... }:
{
  wayland.windowManager.hyprland.settings.input.touchdevice = lib.mkMerge {
    enabled = true;
    output = "eDP-1";
    transform = 3;
  };
}
