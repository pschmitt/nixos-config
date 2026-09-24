{ lib, ... }:
{
  options.services.ppd-react = {
    enable = lib.mkEnableOption "power-profiles-daemon integration service" // {
      default = true;
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

    tdp = {
      enable = lib.mkEnableOption "TDP changes in response to power profiles";

      command = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Command accepting ryzenadj-style TDP limit arguments.";
      };

      profiles = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
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
          }
        );
        default = { };
        description = "TDP limits keyed by power-profiles-daemon profile name.";
      };
    };
  };
}
