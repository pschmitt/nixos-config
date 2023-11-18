{ inputs, lib, config, pkgs, ... }:

{
  # Theming
  gtk = {
    enable = true;
    theme = {
      # name = "Adwaita-dark";
      # package = pkgs.gnome.gnome-themes-extra;
      name = "Colloid-Dark-Nord";
      package = (pkgs.colloid-gtk-theme.override {
        themeVariants = [ "all" ];
        colorVariants = [ "dark" "light" "standard" ];
        tweaks = [ "normal" "nord" ];
      });
    };

    iconTheme = {
      name = "Colloid-nord-dark";
      # Colloid-nord-dark is not technically part of colloid-icon-theme
      package = (pkgs.colloid-icon-theme.override {
        schemeVariants = [ "all" ];
        colorVariants = [ "all" ];
      });
    };

    font = {
      name = "Noto Sans 10";
      package = pkgs.noto-fonts;
    };

    cursorTheme = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
    };

    # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
    gtk3 = {
      extraConfig = { gtk-application-prefer-dark-theme = 1; };
    };

    gtk4 = { extraConfig = { gtk-application-prefer-dark-theme = 1; }; };
  };

  qt = {
    enable = true;
    platformTheme = "gnome";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt6;
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = { color-scheme = "prefer-dark"; };
  };
}
