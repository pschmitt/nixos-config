{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.custom.desktop.theme;
  colorScheme = if cfg.preferDark then "prefer-dark" else "default";
  darkTheme = if cfg.preferDark then "1" else "0";
in
{
  imports = [ inputs.catppuccin.homeModules.catppuccin ];

  config = lib.mkMerge [
    {
      custom.desktop.theme.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      catppuccin = {
        enable = true;
        # autoEnable reaches into every catppuccin/nix port, including
        # browsers/terminals/editors we don't want it touching (it broke the
        # build fighting our Firefox extension config). Opt in per desktop
        # component instead.
        autoEnable = false;
        inherit (cfg) flavor accent;

        gtk.icon.enable = true;
        cursors.enable = true;
        mako.enable = true;
        waybar.enable = true;
        hyprland.enable = true;
        hyprlock.enable = true;
        vicinae.enable = true;
      };

      home = {
        packages = cfg.homePackages;

        # Let catppuccin's cursors module (home.pointerCursor) drive
        # gtk.cursorTheme too, instead of only Hyprland/X11.
        pointerCursor.gtk.enable = true;

        sessionVariables.GTK_THEME = cfg.gtk.name;
      };

      gtk = {
        enable = true;
        theme = {
          inherit (cfg.gtk) name package;
        };

        # Catppuccin's gtk module (icons) and cursors module (via
        # home.pointerCursor.gtk.enable, both set via mkDefault) set these
        # directly when enabled; keep our values as a weaker fallback so
        # they only apply if catppuccin theming is turned off.
        iconTheme = lib.mkDefault {
          inherit (cfg.icons) name package;
        };

        font = {
          inherit (cfg.font) name package;
        };

        cursorTheme = lib.mkOptionDefault {
          inherit (cfg.cursor) name package;
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
