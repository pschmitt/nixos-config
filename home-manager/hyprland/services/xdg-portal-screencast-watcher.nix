{ lib, ... }:
{
  wayland.windowManager.hyprland.settings.exec = lib.mkAfter [
    "$ensure1 -j xdg-portal -- $bin_dir/xdg-portal-screencast-watcher.sh"
  ];
}
