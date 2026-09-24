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
    # lan-mouse's wlroots backend reuses the compositor seat keymap for its
    # virtual keyboard, so match the seat default to gk4's GPD keyboard. The
    # built-in HHKB keeps its explicit per-device layout from input.nix.
    config.input.kb_layout = lib.mkForce "gpdpocket4-de,gpdpocket4-us,us,de";

    # lan-mouse presents remote input as a virtual keyboard. Apply the GPD
    # Pocket 4 layout here when gk4's built-in keyboard is controlling ge2.
    device = [
      {
        name = "hl-virtual-keyboard-.lan-mouse-wrapped";
        kb_layout = "gpdpocket4-de,gpdpocket4-us,us,de";
      }
    ];

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
