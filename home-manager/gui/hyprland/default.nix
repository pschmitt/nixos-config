{

  wayland.windowManager.hyprland = {
    # use the version provided by the nixpkgs module
    package = null;
    # TODO switch to lua! see the hyprland-lua branch.
    # current blockers: hypr-dynamic-cursors and hyprgrass
    configType = "hyprlang";
  };

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
