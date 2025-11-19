{ pkgs, lib, ... }:
{
  home.packages = [ pkgs.xhost ];

  # Mirrors ~/.config/hypr/config.d/autostart.conf.
  wayland.windowManager.hyprland.settings."exec-once" = [
    # Startup helper from autostart.conf.
    "systemd-cat --identifier=hyprland-startup $bin_dir/startup.sh"
  ];
}
