{
  lib,
  config,
  pkgs,
  ...
}:
let
  fprintdUsbAutoReset = pkgs.writeShellApplication {
    name = "fprintd-usb-autoreset";
    runtimeInputs = with pkgs; [
      jc
      jq
      libnotify
      systemd
      usbutils
      util-linux
    ];
    text = builtins.readFile ./fprintd-usb-autoreset.sh;
  };
in
{
  services.fprintd.enable = lib.mkDefault true;

  systemd = lib.mkIf config.hardware.fprintd.autoreset.enable {
    services.fprintd-usb-autoreset = {
      description = "Auto-reset fingerprint USB device when fprintd sees no devices";
      after = [
        "dbus.service"
        "fprintd.service"
      ];
      wants = [ "fprintd.service" ];
      environment = {
        NOTIFY = "1";
        DEVICE_NAME = config.hardware.fprintd.autoreset.deviceName;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${fprintdUsbAutoReset}/bin/fprintd-usb-autoreset";
      };
    };

    timers.fprintd-usb-autoreset = {
      description = "Run fprintd USB autoreset periodically";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "1h";
        RandomizedDelaySec = "10m";
      };
    };
  };
}
