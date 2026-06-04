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
              hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor 1 desc:LG")
              hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor 2 desc:Lenovo")
              hl.exec_cmd("hyprctl dispatch focusmonitor desc:LG")
              hl.exec_cmd("hyprctl dispatch workspace 1")
              hl.exec_cmd("zhj pulseaudio::mute-default-source")
          end
        '')
      ];
    }
  ];
}
