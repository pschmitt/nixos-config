{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    "exec-once" = lib.mkBefore (
      let
        workspaceDispatches = [
          "moveworkspacetomonitor 1 desc:LG"
          "moveworkspacetomonitor 2 desc:Lenovo"
          "focusmonitor desc:LG"
          "workspace 1"
        ];
      in
      (map (cmd: "hyprctl dispatch ${cmd}") workspaceDispatches)
      ++ [ "zhj pulseaudio::mute-default-source" ]
    );
  };
}
