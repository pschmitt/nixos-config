{
  lib,
  osConfig ? null,
  ...
}:
let
  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
  hostModulePath = if hostName == null then null else ./host-specific + "/${hostName}.nix";
  hostModule =
    if hostModulePath == null || !(builtins.pathExists hostModulePath) then null else hostModulePath;
in
{
  imports = lib.optional (hostModule != null) hostModule;
}
