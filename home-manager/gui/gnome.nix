_: {
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      show-battery-percentage = true;
    };

    # Resize windows with super+right mouse
    # https://wiki.archlinux.org/title/GNOME#Resize_windows_by_mouse
    "org/gnome/desktop/wm/preferences" = {
      resize-with-right-button = true;
    };

    # close with Super+Shift+C
    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Shift><Super>c" ];
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      next = [ "<Shift><Control>Right" ];
      previous = [ "<Shift><Control>Left" ];
      play = [ "<Shift><Control>Up" ];

      # Reference custom key bindings from below
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "kitty";
      command = "kitty";
      binding = "<Super>Return";
    };
  };
}
