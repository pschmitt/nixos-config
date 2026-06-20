{
  lib,
  pkgs,
  ...
}:
let
  gsettingsWrapper = pkgs.writeTextFile {
    name = "gsettings";
    destination = "/bin/gsettings";
    executable = true;
    text =
      let
        schema = pkgs.gsettings-desktop-schemas;
        datadir = "${schema}/share/gsettings-schemas/${schema.name}";
      in
      ''
        export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
        ${pkgs.glib}/bin/gsettings "$@"
      '';
  };
in
{
  options.custom.desktop.theme = {
    enable = lib.mkEnableOption "shared desktop theme";

    flavor = lib.mkOption {
      type = lib.types.str;
      default = "mocha";
      description = "Catppuccin flavor to use for theme-aware integrations.";
    };

    systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        gtk3
        gtk4
      ];
      description = "System packages needed for desktop theming.";
    };

    homePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        gnome-themes-extra
        gsettingsWrapper
      ];
      description = "User packages needed for desktop theming.";
    };

    gtk = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Colloid-Dark";
        description = "GTK theme name.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.colloid-gtk-theme;
        description = "GTK theme package.";
      };
    };

    icons = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Tela-circle";
        description = "Icon theme name.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.tela-circle-icon-theme;
        description = "Icon theme package.";
      };
    };

    font = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Noto Sans 10";
        description = "Desktop font.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.noto-fonts;
        description = "Desktop font package.";
      };
    };

    cursor = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Bibata-Modern-Ice";
        description = "Cursor theme name.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bibata-cursors;
        description = "Cursor theme package.";
      };
    };

    qt = {
      platformTheme = lib.mkOption {
        type = lib.types.str;
        default = "adwaita";
        description = "Qt platform theme name.";
      };

      style = lib.mkOption {
        type = lib.types.str;
        default = "adwaita-dark";
        description = "Qt widget style name.";
      };
    };

    preferDark = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether GTK and GNOME should prefer dark mode.";
    };
  };
}
