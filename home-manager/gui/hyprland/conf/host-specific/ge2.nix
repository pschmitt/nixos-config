{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
in
{
  # ge2: pin workspaces to the right monitors on startup.
  wayland.windowManager.hyprland.settings.on = [
    {
      _args = [
        "hyprland.start"
        (mkLuaInline ''
          function()
              hl.dispatch(hl.dsp.workspace.move({ workspace = 1, monitor = "desc:LG" }))
              hl.dispatch(hl.dsp.workspace.move({ workspace = 2, monitor = "desc:Lenovo" }))
              hl.dispatch(hl.dsp.focus({ monitor = "desc:LG" }))
              hl.dispatch(hl.dsp.focus({ workspace = 1 }))
              hl.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ true")
          end
        '')
      ];
    }
  ];
}
