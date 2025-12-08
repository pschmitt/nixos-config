{ config, lib, ... }:
{
  # See https://wiki.hyprland.org/Configuring/Variables/ and /Animations/ for docs.
  wayland.windowManager.hyprland.settings =
    let
      cursorTheme = config.gtk.cursorTheme.name;
      cursorSize = "24";
    in
    lib.mkMerge [
      {
        env = [
          "HYPRCURSOR_THEME,${cursorTheme}"
          "HYPRCURSOR_SIZE,${cursorSize}"

          # legacy
          "XCURSOR_THEME,${cursorTheme}"
          "XCURSOR_SIZE,${cursorSize}"
        ];

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
          bezier = [ "myBezier, 0.05, 0.9, 0.1, 1.05" ];
          animation = [
            "windows, 1, 3, myBezier"
            "windowsOut, 1, 3, default, popin 80%"
            "border, 1, 10, default"
            "borderangle, 1, 8, default"
            "fade, 1, 3, default"
            "workspaces, 1, 2, default"
            "layersIn, 1, 1.5, default, popin"
          ];
        };

        # GTK settings import helper script.
        exec = [ "$sway_bin_dir/import-gsettings.sh" ];
      }
    ];
}
