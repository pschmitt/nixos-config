{ lib, pkgs, ... }:
{
  wayland.windowManager.hyprland.settings.exec = lib.mkAfter [
    "$ensure1 -j hyprevents -- ${pkgs.hyprevents}/bin/hyprevents --file $bin_dir/hyprevents-handler.sh"
  ];
}
