{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.desktop.theme;
  colorScheme = if cfg.preferDark then "prefer-dark" else "default";
  darkTheme = if cfg.preferDark then "1" else "0";
in
{
  config = lib.mkMerge [
    {
      custom.desktop.theme.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home = {
        packages = cfg.homePackages;

        # Drives gtk.cursorTheme too, via home-manager's own
        # home.pointerCursor.gtk.enable.
        pointerCursor = {
          enable = true;
          gtk.enable = true;
          inherit (cfg.cursor) name package;
        };

        # GTK4 needs an explicit variant to activate prefers-color-scheme in
        # themes such as adw-gtk3.
        sessionVariables.GTK_THEME = if cfg.preferDark then "${cfg.gtk.name}:dark" else cfg.gtk.name;
      };

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

        gtk3.extraConfig.gtk-application-prefer-dark-theme = darkTheme;
        gtk4 = {
          extraConfig.gtk-application-prefer-dark-theme = darkTheme;
          theme = null;
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
    })
  ];
}
