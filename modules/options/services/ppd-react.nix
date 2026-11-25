{ lib, ... }:
{
  options.services.ppd-react = {
    enable = lib.mkEnableOption "power-profiles-daemon integration service" // {
      default = true;
    };

    onlyStopUnitsOnBattery = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only stop configured units in power-saver while on battery power.";
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show desktop notifications when power profiles or external power change service state.";
    };

    stopSystemdUnitsOnPowerSaver = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "System-level systemd units to stop when power-saver starts.";
    };

    resumeSystemdUnitsOnPowerSaverExit = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "System-level systemd units to resume, if previously active, when leaving power-saver.";
    };

    stopUserSystemdUnitsOnPowerSaver = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "User-level systemd units to stop when power-saver starts.";
    };

    resumeUserSystemdUnitsOnPowerSaverExit = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "User-level systemd units to resume, if previously active, when leaving power-saver.";
    };

    defaults = {
      brightness = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 30;
        description = "Battery brightness percentage when the profile has no override.";
      };
      connectedMinimumBrightness = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 50;
        description = "Minimum brightness on external power when the profile has no override.";
      };
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            tdp = lib.mkOption {
              type = lib.types.nullOr (lib.types.ints.between 1 1000);
              default = null;
              description = "TDP in watts for all limits, used on external power and as the battery fallback.";
            };
            batteryTdp = lib.mkOption {
              type = lib.types.nullOr (lib.types.ints.between 1 1000);
              default = null;
              description = "Optional battery TDP in watts for all limits.";
            };
            brightness = lib.mkOption {
              type = lib.types.nullOr (lib.types.ints.between 0 100);
              default = null;
              description = "Display brightness percentage on battery.";
            };
            connectedMinimumBrightness = lib.mkOption {
              type = lib.types.nullOr (lib.types.ints.between 0 100);
              default = null;
              description = "Minimum display brightness percentage on external power.";
            };
          };
        }
      );
      default = { };
      description = "TDP and brightness settings keyed by power profile.";
    };

    tdp = {
      enable = lib.mkEnableOption "TDP changes in response to power profiles";

      command = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Command accepting ryzenadj-style TDP limit arguments.";
      };
    };
  };
}
