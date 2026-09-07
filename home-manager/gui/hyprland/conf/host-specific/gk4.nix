{ lib, ... }:
let
  h = import ../../lua-helpers.nix { inherit lib; };
  inherit (h) execBind;
  layout = import ../layout-helpers.nix { inherit lib; };
in
{
  # GK4 (GPD Pocket 4): internal panel is physically rotated 90° and is HiDPI.
  host.internalMonitor = {
    transform = 3;
    scale = 1.666;
    # GK4: sensor-proxy already compensates the chassis mount, so keep
    # iio-hyprland's orientation map neutral here.
    iioTransformMap = [
      0
      1
      2
      3
    ];
  };
  # hyprctl-reported mode is 1600x2560 pre-transform; transform=3 swaps it to
  # a rendered 2560x1600 canvas, and scale divides that down to logical px --
  # matches Noctalia's own startup log: "logical=1536x960". Single internal
  # panel, no dock/external monitor on this host.
  host.lockscreenOutputs = [
    {
      name = "eDP-1";
      logicalWidth = 1536.0;
      logicalHeight = 960.0;
    }
  ];

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
