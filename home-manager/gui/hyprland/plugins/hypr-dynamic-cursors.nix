{ inputs, pkgs, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [
      inputs.hypr-dynamic-cursors.packages.${pkgs.stdenv.hostPlatform.system}.hypr-dynamic-cursors
    ];
  };

  wayland.windowManager.hyprland.settings = {
    plugin.dynamic-cursors = {
      enabled = true;
      mode = "rotate";
    };
  };
}
