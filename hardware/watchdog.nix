{ config, lib, ... }:
let
  cfg = config.hardware.watchdog;
  isPhysical = cfg.implementation == "hardware";
  moduleName = if cfg.implementation == "softdog" then "softdog" else "virtio_watchdog";
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf isPhysical {
        services.watchdogd.enable = true;
      })

      (lib.mkIf (!isPhysical) {
        boot.kernelModules = [ moduleName ];

        systemd.settings.Manager = {
          RuntimeWatchdogSec = "30s";
          RebootWatchdogSec = "5min";
        };
      })
    ]
  );
}
