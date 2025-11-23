{
  inputs,
  pkgs,
  ...
}:
{
  wayland.windowManager.hyprland.plugins = [
    inputs.hyprtasking.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  wayland.windowManager.hyprland.settings = {
    bind = [ "SUPER, g, hyprtasking:toggle, all" ];
    plugin.hyprtasking = {
      layout = "grid";
    };
  };
}
