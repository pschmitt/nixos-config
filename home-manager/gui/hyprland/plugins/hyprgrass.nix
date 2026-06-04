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
            workspace_swipe_fingers = 3,
            workspace_swipe_edge    = "d",
            long_press_delay        = 400,
            edge_margin             = 10,
            resize_on_border_long_press = true,
        } } })

        hl.plugin.hyprgrass.bind({ gesture = "edge:d:u",  action = hl.dsp.exec_cmd("~/.config/hypr/bin/toggle-soft-keyboard.sh") })
        hl.plugin.hyprgrass.bind({ gesture = "swipe:4:d", action = hl.dsp.window.kill() })
        hl.plugin.hyprgrass.bind({ gesture = "swipe:4:u", action = hl.dsp.exec_cmd("kitty") })

        hl.plugin.hyprgrass.bind({ gesture = "longpress:2", action = hl.dsp.window.drag(),   mouse = true })
        hl.plugin.hyprgrass.bind({ gesture = "longpress:3", action = hl.dsp.window.resize(), mouse = true })
    end
  '';
}
