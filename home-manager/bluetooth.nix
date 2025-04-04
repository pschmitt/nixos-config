{ osConfig, pkgs, ... }:
{
  services.mpris-proxy.enable = osConfig.hardware.bluetooth.enable;

  systemd.user.services.bluez-headset-callback = {
    Unit = {
      Description = "Bluez Headset Callback";
    };
    Service = {
      ExecStart = "${pkgs.bluez-headset-callback}/bin/bluez-headset-callback.sh";
      Restart = "always";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
