{ ... }:
{
  dconf.settings = {
    # Resize windows with super+right mouse
    # https://wiki.archlinux.org/title/GNOME#Resize_windows_by_mouse
    "org/gnome/desktop/wm/preferences" = {
      resize-with-right-button = true;
    };
  };
}
