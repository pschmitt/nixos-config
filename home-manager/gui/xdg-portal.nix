{
  pkgs,
  ...
}:
{

  # The quick and dirty config below:
  # xdg.portal.config.common.default = "*";
  # reproduces the < 1.17 behavior,  which uses the first portal
  # implementation found in lexicographical order
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
    config.common = {
      default = [
        "hyprland"
        "gtk"
      ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
      "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
    };
  };
}
