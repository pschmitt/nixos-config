{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      bind = [
        # fake f1 -> scratchpad terminal
        # NOTE We might want to consider to set:
        # resolve_binds_by_sym = 1
        # -> would make this keybind less keymap-dependent.
        # We'd then map on "grave" instead of dead_circumflex.
        "CTRL, dead_circumflex, exec, $bin_dir/scratchpad.sh term"
        "CTRL, escape, exec, $bin_dir/scratchpad.sh term"
      ];
      input.touchdevice = {
        enabled = true;
        output = "eDP-1";
        transform = 3;
      };
    }
  ];
}
