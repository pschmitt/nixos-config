{ lib, ... }:
let
  tdpProfile = lib.types.submodule {
    options = {
      stapmLimit = lib.mkOption {
        type = lib.types.ints.between 1000 1000000;
        description = "STAPM limit in milliwatts.";
      };
      fastLimit = lib.mkOption {
        type = lib.types.ints.between 1000 1000000;
        description = "Fast PPT limit in milliwatts.";
      };
      slowLimit = lib.mkOption {
        type = lib.types.ints.between 1000 1000000;
        description = "Slow PPT limit in milliwatts.";
      };
      apuSlowLimit = lib.mkOption {
        type = lib.types.ints.between 1000 1000000;
        description = "APU slow PPT limit in milliwatts.";
      };
    };
  };
in
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

    brightness = {
      batteryPercent = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 30;
        description = "Display brightness percentage on battery, unless overridden by the active profile.";
      };
      batteryProfiles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.ints.between 0 100);
        default = { };
        description = "Battery brightness percentages keyed by power profile.";
      };
      connectedMinimumPercent = lib.mkOption {
        type = lib.types.ints.between 0 100;
        default = 50;
        description = "Minimum display brightness on external power, unless overridden by the active profile.";
      };
      connectedProfiles = lib.mkOption {
        type = lib.types.attrsOf (lib.types.ints.between 0 100);
        default = { };
        description = "Minimum external-power brightness percentages keyed by power profile.";
      };
    };

    tdp = {
      enable = lib.mkEnableOption "TDP changes in response to power profiles";

      command = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Command accepting ryzenadj-style TDP limit arguments.";
      };

      profiles = lib.mkOption {
        type = lib.types.attrsOf tdpProfile;
        default = { };
        description = "TDP limits keyed by power-profiles-daemon profile name.";
      };

      batteryProfiles = lib.mkOption {
        type = lib.types.attrsOf tdpProfile;
        default = { };
        description = "TDP limits keyed by power-profiles-daemon profile name while on battery.";
      };

    };
  };
}
