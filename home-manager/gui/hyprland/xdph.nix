{ pkgs, ... }:
{
  home.packages = [
    pkgs.hyprland-share-picker-gtk
  ];

  # Mirror ~/.config/hypr/xdph.conf for xdg-desktop-portal-hyprland.
  xdg.configFile."hypr/xdph.conf".text = ''
    screencopy {
      allow_token_by_default = true
      custom_picker_binary = ${pkgs.hyprland-share-picker-gtk}/bin/hyprland-share-picker-gtk
      cursor_mode = 2 # embedded: share the cursor in screencasts
    }
  '';

  xdg.configFile."hypr/xdph-picker-gtk.conf".text = ''
    # Configuration for hyprland-share-picker-gtk.
    # `columns` specifies the number of tile columns in Window and Screen tabs (default: 1).
    columns = 2

    # How the hovered and selected window or screen is marked in Hyprland
    # (slurp-like overlay). `mode` is either `highlight` (tint the target) or
    # `dim` (dim everything but the target); `dim_factor` is the dim opacity.
    # The target stays lightly tinted and outlined in either mode so it remains
    # obvious while comparing sources or reviewing a drawn region.
    highlight {
      mode = dim
      dim_factor = 0.62
      color = #60a5fa
      fill_opacity = 0.16
      border = true
      border_size = 4
      # dim_color = rgba(0, 0, 0, 1.0) # or hex like #000000
    }

    # Preview settings. `refresh_rate` is the focused (hovered or selected)
    # source rate; other visible tiles run at 1 fps to save CPU.
    preview {
      scale = 0.35
      jpeg_quality = 78
      refresh_rate = 30
    }
  '';
}
