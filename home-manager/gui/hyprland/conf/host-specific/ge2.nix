{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
in
{
  # AU Optronics 0x31A6 internal panel: 1920x1200 @ scale 1.0, no rotation
  # (verified via `hyprctl monitors -j`, 2026-09-07) -- so logical == mode.
  host.internalMonitor = {
    logicalWidth = 1920.0;
    logicalHeight = 1200.0;
  };

  wayland.windowManager.hyprland.settings = {
    workspace_rule = [
      {
        workspace = "1";
        monitor = "desc:LG";
        default = true;
      }
      {
        workspace = "2";
        monitor = "desc:AU Optronics";
        default = true;
      }
    ];

    on = [
      {
        _args = [
          "hyprland.start"
          (mkLuaInline ''
            function()
                hl.dispatch(hl.dsp.focus({ monitor = "desc:LG" }))
                hl.dispatch(hl.dsp.focus({ workspace = 1 }))
                hl.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ true")
            end
          '')
        ];
      }
    ];
  };
}
