{ pkgs, ... }:
{
  imports = [ ./nrf.nix ];

  # Only imported on Bluetooth hosts (see home.nix import gating).
  services.mpris-proxy.enable = true;

  systemd.user.services.bluez-headset-callback = {
    Unit = {
      Description = "Bluez Headset Callback";
      # Needs WAYLAND_DISPLAY (for the noctalia/osd toast) which is only
      # imported into the systemd user manager once Hyprland's autostart
      # runs dbus-update-activation-environment. default.target activates
      # before that happens, so this must wait on graphical-session.target
      # instead, like the other Hyprland-session services do.
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.bluez-headset-callback}/bin/bluez-headset-callback.sh";
      Restart = "always";
      RestartSec = 10;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
