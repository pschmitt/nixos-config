{ lib, ... }:
{
  # Mirrors ~/.config/hypr/config.d/lock.conf (lock binds + idle rules).
  wayland.windowManager.hyprland.settings = {
    # Lock helpers from lock.conf.
    "$lock" = "$bin_dir/lock.sh";

    bind = [
      "$mod ALT, L, exec, $lock --now"
    ];

    bindl = [
      "$mod CONTROL ALT, L, exec, ~/bin/zhj \"lockscreen::restart\""
      ", switch:off:Lid Switch, exec, $lock"
      ", switch:on:Lid Switch, exec, hyprctl dispatch dpms on"
    ];

    windowrule = [
      "idle_inhibit fullscreen, match:class ^(firefox)$"
      "idle_inhibit always, match:title ^(Picture-in-Picture)$"
      "idle_inhibit fullscreen, match:class ^(Google-chrome)$"
      "idle_inhibit fullscreen, match:class ^(Chromium)$"
    ];
  };
}
