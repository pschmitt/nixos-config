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

        -- workspace_swipe_fingers/workspace_swipe_edge are legacy-only options;
        -- in Lua mode use hyprgrass.gesture (docs/lua_migration.md).
        hl.plugin.hyprgrass.gesture({ pattern = {kind = "swipe", fingers = 3,     direction = "horizontal"}, action = "workspace" })
        hl.plugin.hyprgrass.gesture({ pattern = {kind = "edge",  origin = "down", direction = "horizontal"}, action = "workspace" })

        hl.plugin.hyprgrass.bind({ pattern = {kind = "edge",  origin = "down", direction = "up"},   action = hl.dsp.exec_cmd("~/.config/hypr/bin/toggle-soft-keyboard.sh") })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "swipe", fingers = 4,     direction = "down"}, action = hl.dsp.window.kill() })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "swipe", fingers = 4,     direction = "up"},   action = hl.dsp.exec_cmd("kitty") })

        hl.plugin.hyprgrass.bind({ pattern = {kind = "longpress", fingers = 2}, action = hl.dsp.window.drag(),   mouse = true })
        hl.plugin.hyprgrass.bind({ pattern = {kind = "longpress", fingers = 3}, action = hl.dsp.window.resize(), mouse = true })
    end
  '';
}
