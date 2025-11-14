{ lib, ... }:
{
  imports = [
    ./hyprdynamicmonitors.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./mako.nix
  ];
  # Mirrors ~/.config/hypr/config.d/services.conf.
  wayland.windowManager.hyprland.settings = {
    # Service supervision from services.conf (all still run via $ensure1 helper)
    exec = lib.mkAfter [
      # "$ensure1 -j waybar -- ~/.config/waybar/waybar-cava-wrapper.sh -l debug"
      "$ensure1 -j xdg-portal -- $bin_dir/xdg-portal-screencast-watcher.sh"
      "$ensure1 -j hyprevents -- ~/.config/hypr/hyprevents/hyprevents --file $bin_dir/hyprevents-handler.sh"
      "$ensure1 -j clipboard -- wl-clip-persist --clipboard both"
      "$ensure1 -j clipboard -- wl-paste --type text --watch cliphist store"
      "$ensure1 -j clipboard -- wl-paste --type image --watch cliphist store"
      "$ensure1 -j hints -- hintsd"
    ];

    # KDE Connect / polkit lines remain commented in the original file and are
    # omitted here since other components now manage them.
  };
}
