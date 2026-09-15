{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.fievel;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.services.fievel = {
    enable = lib.mkEnableOption "Fievel keyboard-driven mouse control";

    package = lib.mkPackageOption pkgs "fievel" { };

    settings = lib.mkOption {
      inherit (tomlFormat) type;
      default = { };
      description = ''
        Fievel configuration written to
        ~/.config/fievel/fievel.config. An empty attrset leaves the upstream
        built-in defaults in use (hold F3 and use H/J/K/L for pointer control).
        See the upstream configuration documentation for available settings.
      '';
      example = lib.literalExpression ''
        {
          mode = "hold";
          notify = true;
          keys = {
            free_mouse = "f3";
            left = "h";
            down = "j";
            up = "k";
            right = "l";
          };
        }
      '';
    };

    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional evdev keyboard device for Fievel to read.";
      example = "/dev/input/event3";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."fievel/fievel.config" = lib.mkIf (cfg.settings != { }) {
      source = tomlFormat.generate "fievel.config" cfg.settings;
    };

    systemd.user.services.fievel = {
      Unit = {
        Description = "Fievel keyboard-driven mouse control";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Install.WantedBy = [ "graphical-session.target" ];

      Service = {
        ExecStart =
          let
            args = lib.optionals (cfg.device != null) [
              "--device"
              cfg.device
            ];
          in
          lib.escapeShellArgs ([ (lib.getExe cfg.package) ] ++ args);
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}

# vim: set ft=nix et ts=2 sw=2 :
