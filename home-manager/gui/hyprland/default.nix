{
  wayland.windowManager.hyprland = {
    # use the version provided by the nixpkgs module
    package = null;
    # Hyprland 0.55+ Lua config. home-manager renders settings/extraLuaFiles to
    # ~/.config/hypr/hyprland.lua (and a .luarc.json for LSP support).
    configType = "lua";
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
