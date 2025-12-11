{ config, lib, ... }:
let
  cfg = config.hardware.watchdog;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.implementation == "hardware") {
        services.watchdogd.enable = true;
      })

      (lib.mkIf (cfg.implementation != "hardware") {
        boot.kernelModules = [
          (if cfg.implementation == "softdog" then "softdog" else "virtio_watchdog")
        ];

        systemd.settings.Manager = {
          RuntimeWatchdogSec = "30s";
          RebootWatchdogSec = "5min";
        };
      })
    ]
  );
}
