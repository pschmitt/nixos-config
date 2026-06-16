{
  inputs,
  pkgs,
  ...
}:
{
  # Touchscreen gestures (https://github.com/horriblename/hyprgrass), Lua API via
  # PR #381 (lua-func branch).
  #
  # Load the plugin at RUNTIME via home-manager (hyprctl plugin load in the
  # hyprland.start hook), NOT with hl.plugin.load at config-parse time — loading
  # during parse blocks compositor init and makes the uwsm session time out.
  # Loading a plugin triggers a config reload (PluginSystem.cpp), so the guarded
  # block below re-runs once hl.plugin.hyprgrass exists and the config applies.
  wayland.windowManager.hyprland.plugins = [
    inputs.hyprgrass.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  wayland.windowManager.hyprland.extraConfig = ''
    if hl.plugin.hyprgrass then
        hl.config({ plugin = { hyprgrass = {
            sensitivity             = 6.0,
            long_press_delay        = 400,
            edge_margin             = 10,
            resize_on_border_long_press = true,
        } } })

        -- Dispatch touchscreen workspace swipes directly. Gesture recognition
        -- works here, but Hyprgrass' `workspace` / `emulate_touchpad` paths do
        -- not reliably hand off to the Lua-configured gesture engine.
        hl.plugin.hyprgrass.bind({ pattern = {kind = "swipe", fingers = 3, direction = "left"},  action = hl.dsp.focus({ workspace = "+1" }) })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "swipe", fingers = 3, direction = "right"}, action = hl.dsp.focus({ workspace = "-1" }) })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "edge", origin = "down", direction = "left"},  action = hl.dsp.focus({ workspace = "+1" }) })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "edge", origin = "down", direction = "right"}, action = hl.dsp.focus({ workspace = "-1" }) })

        hl.plugin.hyprgrass.bind({ pattern = {kind = "edge",  origin = "down", direction = "up"},   action = hl.dsp.exec_cmd("~/.config/hypr/bin/toggle-soft-keyboard.sh") })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "swipe", fingers = 4,     direction = "down"}, action = hl.dsp.window.kill() })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "swipe", fingers = 4,     direction = "up"},   action = hl.dsp.exec_cmd("kitty") })

        hl.plugin.hyprgrass.bind({ pattern = {kind = "longpress", fingers = 2}, action = hl.dsp.window.drag(),   mouse = true })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "longpress", fingers = 3}, action = hl.dsp.window.resize(), mouse = true })
    end
  '';
}
