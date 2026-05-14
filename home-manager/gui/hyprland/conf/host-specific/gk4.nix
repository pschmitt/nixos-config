{ lib, ... }:
let
  luaBind = import ../../lib/lua-bind.nix { inherit lib; };
in
{
  wayland.windowManager.hyprland = {
    # Static monitor rule so the initial modeset uses the correct transform/scale.
    # hl.monitor() at top-level adds to monitorRuleMgr before display init,
    # matching the old hyprlang `monitor=eDP-1,preferred,auto,1.666,transform,3`.
    extraConfig = ''
      hl.monitor({output="eDP-1", mode="preferred", position="auto", scale=1.666, transform=3})
    '';

    settings = lib.mkMerge [
      {
        bind = [
          # fake f1 -> scratchpad terminal
          # NOTE We might want to consider to set:
          # resolve_binds_by_sym = 1
          # -> would make this keybind less keymap-dependent.
          # We'd then map on "grave" instead of dead_circumflex.
          (luaBind.mkBind "CTRL, dead_circumflex, exec, ~/.config/hypr/bin/scratchpad.sh term")
          (luaBind.mkBind "CTRL, escape, exec, ~/.config/hypr/bin/scratchpad.sh term")
        ];

        config.input.touchdevice = {
          enabled = true;
          output = "eDP-1";
          transform = 3;
        };
      }
    ];
  };
}
