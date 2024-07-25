{ pkgs, ... }:

let
  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/data/icons/colloid-icon-theme/default.nix
  colloidIconPkg = (
    pkgs.colloid-icon-theme.override {
      schemeVariants = [ "all" ];
      colorVariants = [ "all" ];
    }
  );

  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/data/themes/colloid-gtk-theme/default.nix
  colloidThemePkg = (
    pkgs.colloid-gtk-theme.override {
      themeVariants = [ "all" ];
      colorVariants = [
        "dark"
        "light"
        "standard"
      ];
      tweaks = [
        "normal"
        "nord"
      ];
      sizeVariants = [
        "standard"
        "compact"
      ];
    }
  );

  theme = "Colloid-Dark-Nord";
  themePkg = colloidThemePkg;

  iconTheme = "Tela-circle";
  iconThemePkg = pkgs.tela-circle-icon-theme;

  font = "Noto Sans 10";
  fontPkg = pkgs.noto-fonts;

  cursorTheme = "Bibata-Modern-Ice";
  cursorThemePkg = pkgs.bibata-cursors;
in
{
  home.packages = with pkgs; [
    # icon-library
    arc-icon-theme
    colloidIconPkg
    colloidThemePkg
    flat-remix-icon-theme
    gnome-themes-extra
    numix-icon-theme
    numix-icon-theme-circle
    numix-icon-theme-square
    paper-icon-theme
    papirus-icon-theme
    tela-circle-icon-theme
    tela-icon-theme

    # gsettings wrapper
    (pkgs.writeTextFile {
      name = "gsettings";
      destination = "/bin/gsettings";
      executable = true;
      text =
        let
          schema = pkgs.gsettings-desktop-schemas;
          datadir = "${schema}/share/gsettings-schemas/${schema.name}";
          bin = pkgs.glib;
        in
        ''
          export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
          ${bin}/bin/gsettings "$@"
        '';
    })
  ];

  # Theming
  gtk = {
    enable = true;
    theme = {
      # name = "Adwaita-dark";
      # package = pkgs.gnome.gnome-themes-extra;
      name = theme;
      package = themePkg;
    };

    iconTheme = {
      name = iconTheme;
      package = iconThemePkg;
    };

    font = {
      name = font;
      package = fontPkg;
    };

    cursorTheme = {
      name = cursorTheme;
      package = cursorThemePkg;
    };

    # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
    gtk3 = {
      # FIXME Should this be "true" or "1"?
      extraConfig = {
        gtk-application-prefer-dark-theme = "1";
      };
    };

    # FIXME Should this be "true" or "1"?
    gtk4 = {
      extraConfig = {
        gtk-application-prefer-dark-theme = "1";
      };
    };
  };

  # FIXME qt is a mess on NixOS, for qtct to work even remotely one needs to
  # install qt5ct as a system package (see ./common/gui/theme.nix)
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style = {
      # name = "adwaita-dark";
      # package = pkgs.adwaita-qt6;
      name = "adwaita-dark";
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      # FIXME Below isn't really necessary. The idea here was to try to force
      # nautilus to use the default gtk theme, but this seems to have no effect
      # gtk-theme = theme;
    };
  };
}
