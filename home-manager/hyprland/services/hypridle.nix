{ config, pkgs, ... }:
let
  hyprBinDir = "${config.home.homeDirectory}/.config/hypr/bin";
  hyprIdleCallbackScript = "${hyprBinDir}/hypridle-callback.sh";
  hyprIdleCallbackWrapper = pkgs.writeShellApplication {
    name = "hypridle-callback";
    runtimeInputs = with pkgs; [
      bash
      libnotify
      systemd
    ];
    text = ''
      exec ${hyprIdleCallbackScript} "$@"
    '';
  };
  hyprIdleCallback = "${hyprIdleCallbackWrapper}/bin/hypridle-callback";
in
{
  services.hypridle = {
    enable = true;
    settings = {
      "$callback" = hyprIdleCallback;
      general = {
        lock_cmd = "$callback lock --now";
        unlock_cmd = "$callback unlock";
        on_unlock_cmd = "$callback on-unlock";
        before_sleep_cmd = "$callback sleep";
        after_sleep_cmd = "$callback resume";
        ignore_dbus_inhibit = false;
        ignore_systemd_inhibit = false;
      };
      listener = [
        {
          timeout = 300;
          "on-timeout" = "$callback timeout";
          "on-resume" = "$callback activity";
        }
      ];
    };
  };
}
