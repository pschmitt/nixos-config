{ pkgs, ... }:
{
  imports = [ ./nrf.nix ];

  # Only imported on Bluetooth hosts (see home.nix import gating).
  services.mpris-proxy.enable = true;

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
