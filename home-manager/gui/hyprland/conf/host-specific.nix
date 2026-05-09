{
  lib,
  osConfig ? null,
  ...
}:
let
  inherit (osConfig.networking) hostName;
  hostModulePath = ./host-specific + "/${hostName}.nix";
  hostModule = if !(builtins.pathExists hostModulePath) then null else hostModulePath;
in
{
  imports = lib.optional (hostModule != null) hostModule;

  # Fallback for hosts without a dedicated module: write an empty host.lua
  # so the require("lua.host") in hyprland.lua doesn't error.
  xdg.configFile."hypr/lua/host.lua" = lib.mkDefault {
    text = "-- no host-specific config for ${hostName}\n";
  };
}
