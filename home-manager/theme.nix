{ inputs, lib, config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # icon-library
    arc-icon-theme
    numix-icon-theme
    numix-icon-theme-circle
    numix-icon-theme-square
    flat-remix-icon-theme
    tela-icon-theme
    tela-circle-icon-theme
    (pkgs.colloid-gtk-theme.override {
      themeVariants = [ "all" ];
      colorVariants = [ "dark" "light" "standard" ];
      tweaks = [ "normal" "nord" ];
    })
    (pkgs.colloid-icon-theme.override {
      schemeVariants = [ "all" ];
      colorVariants = [ "all" ];
    })
  ];

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
      name = "Tela-purple-dark";
      package = pkgs.tela-icon-theme;
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
