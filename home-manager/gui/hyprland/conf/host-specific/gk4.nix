{ lib, ... }:
let
  h = import ../../lua-helpers.nix { inherit lib; };
  inherit (h) execBind;
  layout = import ../layout-helpers.nix { inherit lib; };
in
{
  wayland.windowManager.hyprland.settings = {
    # fake F1 (dead_circumflex) -> scratchpad terminal.
    # NOTE: resolve_binds_by_sym = 1 would make this less keymap-dependent
    #       (bind "grave" instead of dead_circumflex).
    bind = [
      (execBind "CTRL + dead_circumflex" "~/.config/hypr/bin/scratchpad.sh term")
      (execBind "CTRL + escape" "~/.config/hypr/bin/scratchpad.sh term")
    ];

    config.input.touchdevice = {
      enabled = true;
      output = "eDP-1";
      transform = 3;
    };
  };

  # Register the window.open subscriber at config-parse time (top-level),
  # not inside hyprland.start, so it catches early XDG autostart windows.
  wayland.windowManager.hyprland.extraConfig = layout.mkStartupLayoutLua {
    rules = [
      {
        class = "firefox";
        workspace = 2;
        refocus = 1;
      }
    ];
  };
}
