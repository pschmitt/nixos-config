{ lib, ... }:
let
  workspaceBatch =
    (lib.concatStringsSep "; " [
      "dispatch moveworkspacetomonitor 1 desc:LG"
      "dispatch moveworkspacetomonitor 2 desc:Lenovo"
      "dispatch focusmonitor desc:Lenovo"
      "dispatch workspace 2"
      "dispatch focusmonitor desc:LG"
      "dispatch workspace 1"
    ])
    + ";";
in
{
  wayland.windowManager.hyprland.settings."exec-once" = lib.mkAfter [
    # Place workspaces on the intended monitors at session start.
    ''hyprctl --batch "${workspaceBatch}"''

    # Mute default mic on login.
    "zhj pulseaudio::mute-default-source"
  ];
}
