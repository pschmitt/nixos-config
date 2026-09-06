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

    # Highlighting for hovered and selected window or screen in Hyprland (slurp-like overlay).
    # `highlight_mode` is either `highlight` (tint the target) or `dim` (dim
    # everything but the target). `dim_factor` is the dim opacity (0.0 - 1.0).
    highlight_mode = dim
    dim_factor = 0.55
    # dim_color = rgba(0, 0, 0, 1.0) # or hex like #000000
    # highlight_color = rgba(59, 130, 246, 1.0) # or hex like #3b82f6
    # highlight_fill_opacity = 0.22
    # highlight_border_size = 3

    # Preview settings. `refresh_rate` is in frames per second. Settings apply when the picker opens.
    preview {
      scale = 0.35
      jpeg_quality = 78
      refresh_rate = 4
    }
  '';
}
