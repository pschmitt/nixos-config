{ pkgs, inputs, ... }:
let
  dynamicCursors = inputs.hypr-dynamic-cursors.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Dynamic cursor effects (https://github.com/VirtCode/hypr-dynamic-cursors).
  #
  # Loaded at RUNTIME via home-manager (not hl.plugin.load at parse time, which
  # blocks compositor init). The plugin load triggers a config reload, so the
  # guarded block runs once hl.plugin.dynamic_cursors exists.
  # Lua config section is `plugin.dynamic_cursors` (underscore).
  wayland.windowManager.hyprland.plugins = [
    dynamicCursors
  ];

  wayland.windowManager.hyprland.extraConfig = ''
    if hl.plugin.dynamic_cursors then
        hl.config({ plugin = { dynamic_cursors = {
            enabled = true,
            mode    = "rotate",
        } } })
    end
  '';
}
