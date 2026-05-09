{
  imports = [
    # NOTE Below plugins conflict with one another!
    # ./hyprexpo.nix
    # ./hyprspace.nix
    # ./hyprtasking.nix

    ./hyprgrass.nix
    ./hypr-dynamic-cursors.nix
    ./quickshell-overview.nix
    ./xtra-dispatchers.nix
  ];

  xdg.configFile."hypr/lua/plugins.lua".text = ''
    require("lua.plugin-hyprgrass")
    require("lua.plugin-dynamic-cursors")
    require("lua.plugin-xtra-dispatchers")
    require("lua.plugin-quickshell")
  '';
}
