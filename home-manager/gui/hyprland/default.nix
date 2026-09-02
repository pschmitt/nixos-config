{
  wayland.windowManager.hyprland = {
    # use the version provided by the nixpkgs module
    package = null;
    # UWSM owns the Hyprland systemd session integration.
    systemd.enable = false;
    # Hyprland 0.55+ Lua config. home-manager renders settings/extraLuaFiles to
    # ~/.config/hypr/hyprland.lua (and a .luarc.json for LSP support).
    configType = "lua";
  };

  imports = [
    ./bin
    ./conf
    ./plugins
    ./quickshell-bar
    ./services
    ./tools
    ./waybar
    ./xdph.nix
  ];
}
