{ lib, ... }:
let
  h = import ../lua-helpers.nix { inherit lib; };
  inherit (h) execBind execBindLocked;
  lock = "~/.config/hypr/bin/lock.sh";
in
{
  # Lock binds + idle-inhibit window rules.
  wayland.windowManager.hyprland.settings = {
    bind = [
      (execBind "SUPER + ALT + L" "${lock} --now")
      # locked = fires even while the screen is locked
      (execBindLocked "SUPER + CONTROL + ALT + L" ''~/bin/zhj "lockscreen::restart"'')
      (execBindLocked "switch:off:Lid Switch" lock)
      (execBindLocked "switch:on:Lid Switch" "hyprctl dispatch dpms on")
    ];

    window_rule = [
      {
        match.class = "^(firefox)$";
        idle_inhibit = "fullscreen";
      }
      {
        match.title = "^(Picture-in-Picture)$";
        idle_inhibit = "always";
      }
      {
        match.class = "^(Google-chrome)$";
        idle_inhibit = "fullscreen";
      }
      {
        match.class = "^(Chromium)$";
        idle_inhibit = "fullscreen";
      }
    ];
  };
}
