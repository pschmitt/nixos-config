{
  # Mirror ~/.config/hypr/xdph.conf for xdg-desktop-portal-hyprland.
  xdg.configFile."hypr/xdph.conf".text = ''
    screencopy {
      allow_token_by_default = true
      cursor_mode = 2 # embedded: share the cursor in screencasts
    }
  '';
}
