{ lib, osConfig, ... }:
let
  luaBind = import ../lib/lua-bind.nix { inherit lib; };

  firefoxPip = "match:class ^(firefox)$, match:title ^(Picture-in-Picture)$";
  firefoxSharing = "match:class ^(firefox)$, match:title ^(.*Sharing Indicator)$";
  xdph = "match:class ^(hyprland-share-picker)$";
  zoom = "match:class ^(zoom)$";
  gcr = "match:class ^(gcr-prompter)$";
  peeppee = "match:class ^.*(-peepee)$";
  porn = "match:title (?i).*porn.*";
  bitwarden = "match:title (?i).*bitwarden.*";
in
{
  wayland.windowManager.hyprland.settings = lib.mkMerge [
    {
      window_rule = map luaBind.mkWindowRule (
        [
          "float on, ${firefoxPip}"
          "pin on, ${firefoxPip}"
          "float on, ${firefoxSharing}"
          "suppress_event fullscreen, ${firefoxSharing}"
          "suppress_event maximize, ${firefoxSharing}"
          "pin on, ${xdph}"
          "suppress_event fullscreen, ${zoom}"
          "pin on, ${gcr}"
          "stay_focused on, ${gcr}"
          "no_screen_share on, ${gcr}"
          "no_screen_share on, match:tag noscreenshare"
          "no_screen_share on, ${peeppee}"
          "no_screen_share on, ${porn}"
          "no_screen_share on, ${bitwarden}"
        ]
        ++ lib.optionals (osConfig.networking.hostName != "ge2") [
          "workspace 2, match:class ^(firefox)$"
        ]
      );
    }
  ];
}
