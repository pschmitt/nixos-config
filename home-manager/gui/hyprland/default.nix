{
  # use the version provided by the nixpkgs module
  wayland.windowManager.hyprland.package = null;

  imports = [
    ./bin
    ./conf
    ./plugins
    ./services
    ./tools
    ./waybar
    ./xdph.nix
  ];
}
