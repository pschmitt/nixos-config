{ inputs, pkgs, ... }:

let
  theme = "Colloid-Dark";
  themePkg = pkgs.colloid-gtk-theme;
  # theme = "catppuccin-mocha-blue-standard";
  # themePkg = pkgs.catppuccin-gtk.override {
  #   accents = [ "blue" ];
  #   # variant = osConfig.catppuccin.flavor;
  #   variant = "mocha";
  #   # size = "compact";
  # };

  iconTheme = "Tela-circle";
  iconThemePkg = pkgs.tela-circle-icon-theme;

  font = "Noto Sans 10";
  fontPkg = pkgs.noto-fonts;

  cursorTheme = "Bibata-Modern-Ice";
  cursorThemePkg = pkgs.bibata-cursors;
in
{
  imports = [ inputs.catppuccin.homeModules.catppuccin ];

  # catppuccin = {
  #   enable = true;
  #   flavor = osConfig.catppuccin.flavor;
  #   nvim.enable = false;
  # };

  home.packages = with pkgs; [
    gnome-themes-extra

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
    gtk3.extraConfig.gtk-application-prefer-dark-theme = "1";
    gtk4.extraConfig.gtk-application-prefer-dark-theme = "1";
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    # platformTheme.name = "kvantum"; # required for catpuccin
    style = {
      name = "adwaita-dark";
      # name = "kvantum"; # required for catpuccin
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = theme;
    };
  };

  home.sessionVariables = {
    GTK_THEME = theme;
  };
}
