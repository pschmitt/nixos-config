{
  inputs,
  pkgs,
  ...
}:
{
  imports = [ inputs.flatpaks.homeModule ];

  services.flatpak = {
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    packages = [
      # NOTE The "//" are here cause we omitted the cpu arch
      # "flathub:app/com.obsproject.Studio//stable"
      # "flathub:runtime/com.obsproject.Studio.Plugin.DroidCam//stable"

      "flathub:app/org.gimp.GIMP//stable"
    ];
    # overrides = {
    #   "com.obsproject.Studio" = {
    #     filesystems = [
    #       "/nix:ro"
    #       "/run/current-system/sw/bin:ro"
    #     ];
    #   };
    # };
  };

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
