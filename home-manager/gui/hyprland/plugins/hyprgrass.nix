{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pkg = inputs.hyprgrass.packages.${pkgs.stdenv.hostPlatform.system}.default;
  so = lib.findFirst (p: lib.hasSuffix ".so" (toString p)) (throw "hyprgrass: no .so found") (
    lib.filesystem.listFilesRecursive "${pkg}/lib"
  );
in
{
  xdg.configFile."hypr/lua/plugin-hyprgrass.lua".text = ''
    hl.plugin.load("${so}")

    hl.config({
        plugin = {
            touch_gestures = {
                sensitivity                = 6.0,
                workspace_swipe_fingers    = 3,
                workspace_swipe_edge       = "d",
                long_press_delay           = 400,
                resize_on_border_long_press = true,
                edge_margin                = 10,
                emulate_touchpad_swipe     = true,

                ["hyprgrass-bind"] = {
                    ", edge:d:u, exec, ~/.config/hypr/bin/toggle-soft-keyboard.sh",
                    ", swipe:4:d, killactive",
                    ", swipe:4:u, exec, kitty",
                    -- FIXME: ", pinch:3:i, killactive",
                    -- FIXME: ", pinch:3:o, exec, kitty",
                },
                ["hyprgrass-bindm"] = {
                    ", longpress:2, movewindow",
                    ", longpress:3, resizewindow",
                },
            },
        },
    })
  '';
}
