{ pkgs, ... }:
let
  a2dpReconnect = pkgs.writeShellApplication {
    name = "bluetooth-a2dp-reconnect";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.pulseaudio
      pkgs.systemd
    ];
    text = builtins.readFile ./scripts/bluetooth-a2dp-reconnect.sh;
  };
in
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

  # A PipeWire/WirePlumber restart (config change, crash) drops the A2DP
  # transport of connected headsets. Wanted by wireplumber.service, so this
  # runs again every time the audio stack (re)starts.
  systemd.user.services.bluetooth-a2dp-reconnect = {
    Unit = {
      Description = "Reconnect A2DP on Bluetooth headsets after an audio stack restart";
      After = [ "wireplumber.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${a2dpReconnect}/bin/bluetooth-a2dp-reconnect";
    };
    Install = {
      WantedBy = [ "wireplumber.service" ];
    };
  };
}
