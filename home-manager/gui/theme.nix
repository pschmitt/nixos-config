{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.custom.theme;
  colorScheme = if cfg.preferDark then "prefer-dark" else "default";
  darkTheme = if cfg.preferDark then "1" else "0";
in
{
  imports = [ inputs.catppuccin.homeModules.catppuccin ];

  config = lib.mkMerge [
    {
      custom.theme.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      catppuccin = {
        enable = true;
        autoEnable = false;
      };

      home.packages = cfg.homePackages;

      gtk = {
        enable = true;
        theme = {
          inherit (cfg.gtk) name package;
        };

        iconTheme = {
          inherit (cfg.icons) name package;
        };

        font = {
          inherit (cfg.font) name package;
        };

        cursorTheme = {
          inherit (cfg.cursor) name package;
        };

        gtk3.extraConfig.gtk-application-prefer-dark-theme = darkTheme;
        gtk4 = {
          extraConfig.gtk-application-prefer-dark-theme = darkTheme;
          inherit (config.gtk) theme;
        };
      };

      qt = {
        enable = true;
        platformTheme.name = cfg.qt.platformTheme;
        style.name = cfg.qt.style;
      };

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = colorScheme;
          gtk-theme = cfg.gtk.name;
        };
      };

      home.sessionVariables = {
        GTK_THEME = cfg.gtk.name;
      };
    })
  ];
}
