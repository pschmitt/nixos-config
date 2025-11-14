{ lib, ... }:
{
  # Mirrors ~/.config/hypr/config.d/swag.conf (decorations + animations).
  # See https://wiki.hyprland.org/Configuring/Variables/ and /Animations/ for docs.
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      # Decoration/animation tuning from swag.conf.
      decoration = {
        rounding = 2;
        dim_inactive = true;
        dim_strength = 0.1;

        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = false;
          size = 3;
          passes = 1;
          new_optimizations = true;
        };
      };

      animations = {
        enabled = true;
        bezier = lib.mkAfter [ "myBezier, 0.05, 0.9, 0.1, 1.05" ];
        animation = lib.mkAfter [
          "windows, 1, 3, myBezier"
          "windowsOut, 1, 3, default, popin 80%"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 3, default"
          "workspaces, 1, 2, default"
        ];
      };

      # GTK settings import helper script.
      exec = lib.mkAfter [ "$sway_bin_dir/import-gsettings.sh" ];
    }
  ];
}
