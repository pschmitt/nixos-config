{ lib, ... }:
let
  luaBind = import ../lib/lua-bind.nix { inherit lib; };
  binDir = "~/.config/hypr/bin";
  lock = "${binDir}/lock.sh";
in
{
  wayland.windowManager.hyprland.settings = {
    bind = [
      (luaBind.mkBind "SUPER ALT, L, exec, ${lock} --now")
      (luaBind.mkLockedBind "SUPER CONTROL ALT, L, exec, ~/bin/zhj \"lockscreen::restart\"")
      (luaBind.mkLockedBind ", switch:off:Lid Switch, exec, ${lock}")
      (luaBind.mkLockedBind ", switch:on:Lid Switch, exec, hyprctl dispatch dpms on")
    ];

    window_rule = map luaBind.mkWindowRule [
      "idle_inhibit fullscreen, match:class ^(firefox)$"
      "idle_inhibit always, match:title ^(Picture-in-Picture)$"
      "idle_inhibit fullscreen, match:class ^(Google-chrome)$"
      "idle_inhibit fullscreen, match:class ^(Chromium)$"
    ];
  };
}
