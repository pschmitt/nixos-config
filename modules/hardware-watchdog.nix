{ config, lib, ... }:
let
  cfg = config.hardware.watchdog;
  isRpi = config.hardware.type == "rpi";
  isHardware = cfg.implementation == "hardware";
  moduleName = if cfg.implementation == "softdog" then "softdog" else "virtio_watchdog";
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (isHardware && isRpi) {
        boot.kernelModules = [ "bcm2835_wdt" ];
      })

      (lib.mkIf (!isHardware) {
        boot.kernelModules = [ moduleName ];
      })

      {
        systemd.settings.Manager = {
          RuntimeWatchdogSec = "30s";
          RebootWatchdogSec = "5min";
        };
      }
    ]
  );
}
