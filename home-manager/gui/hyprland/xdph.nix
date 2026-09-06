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

    # Highlighting for hovered and selected window or screen in Hyprland
    # highlight_border_color = rgba(53, 132, 228, 1.0)
    # highlight_border_size = 5

    # Preview settings. `refresh_rate` is in frames per second. Settings apply when the picker opens.
    preview {
      scale = 0.35
      jpeg_quality = 78
      refresh_rate = 4
    }
  '';
}
