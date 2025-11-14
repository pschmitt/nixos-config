{ lib, ... }:
{
  # Mirrors ~/.config/hypr/config.d/lock.conf (lock binds + idle rules).
  wayland.windowManager.hyprland.settings = {
    # Lock helpers from lock.conf.
    "$lock" = "$bin_dir/lock.sh";

    bind = lib.mkAfter [
      "$mod ALT, L, exec, $lock --now"
    ];

    bindl = lib.mkAfter [
      "$mod CONTROL ALT, L, exec, ~/bin/zhj \"lockscreen::restart\""
      ", switch:off:Lid Switch, exec, $lock"
      ", switch:on:Lid Switch, exec, hyprctl dispatch dpms on"
    ];

    windowrule = lib.mkAfter [
      "idleinhibit fullscreen, class:^(firefox)$"
      "idleinhibit always, title:^(Picture-in-Picture)$"
      "idleinhibit fullscreen, class:^(Google-chrome)$"
      "idleinhibit fullscreen, class:^(Chromium)$"
    ];
  };
}
