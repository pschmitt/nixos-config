{ config, pkgs, ... }:
let
  hyprIdleCallbackWrapper = pkgs.writeShellApplication {
    name = "hypridle-callback";
    runtimeInputs = with pkgs; [
      bash
      libnotify
      systemd
    ];
    text = ''
      exec ${config.home.homeDirectory}/.config/hypr/bin/hypridle-callback.sh "$@"
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
        # Wait for the lockscreen to be active before going to sleep
        # https://wiki.hypr.land/Hypr-Ecosystem/hypridle/#:~:text=inhibit%5Fsleep
        inhibit_sleep = 3;
        # FIXME Wouldn't below just start another instance of hyprlock?
        lock_cmd = "$callback lock";
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
