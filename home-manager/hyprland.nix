{
  config,
  ...
}:
{
  imports = [
    ./hyprdynamicmonitor.nix
  ];

  xdg.configFile."hypr/config.d/nixos.conf" = {
    text = ''
      # Managed by Home Manager (home-manager/hyprland.nix)
      # Ensure hyprland.conf sources this file:
      #   source = $config_dir/nixos.conf
      #
      # Include the HyprDynamicMonitors output so Hyprland uses the generated layout.
      source = $config_dir/91-hdm-monitors.conf
    '';
  };
}
