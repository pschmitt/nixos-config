{ lib, ... }:
let
  inherit (lib.generators) mkLuaInline;
in
{
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
