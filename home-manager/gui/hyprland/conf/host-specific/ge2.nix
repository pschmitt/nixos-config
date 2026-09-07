{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
in
{
  # Both verified via `hyprctl monitors -j`, 2026-09-07: scale 1.0, no
  # rotation on either, so logical == mode for both.
  #
  # AU Optronics 0x31A6 internal panel: 1920x1200.
  #
  # LG HDR WQHD external monitor: 3440x1440, connected as DP-3 at the time
  # of writing. Unlike eDP-1 (a stable internal-panel name on every host),
  # an external connector's name is dock/port-dependent and can change on a
  # different cable/hub/port -- if the lockscreen widgets stop appearing on
  # the external monitor after a docking change, re-check this with
  # `hyprctl monitors -j` and update the name here.
  host.lockscreenOutputs = [
    {
      name = "eDP-1";
      logicalWidth = 1920.0;
      logicalHeight = 1200.0;
    }
    {
      name = "DP-3";
      logicalWidth = 3440.0;
      logicalHeight = 1440.0;
    }
  ];

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
