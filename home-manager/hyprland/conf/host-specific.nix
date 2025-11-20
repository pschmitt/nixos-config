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
}
