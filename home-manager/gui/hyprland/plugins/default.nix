{
  imports = [
    # Keep Hyprland plugins off while migrating to Lua config.
    # hyprgrass currently uses Hyprland's legacy plugin config API and
    # reloads config on init, which breaks a Lua-configured session.
    # ./hyprexpo.nix
    # ./hyprspace.nix
    # ./hyprtasking.nix
    # ./hyprgrass.nix
    # ./hypr-dynamic-cursors.nix
    ./quickshell-overview.nix
  ];
}
