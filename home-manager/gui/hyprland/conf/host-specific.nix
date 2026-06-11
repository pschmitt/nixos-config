{
  hostname,
  lib,
  ...
}:
let
  hostModulePath = ./host-specific + "/${hostname}.nix";
  hostModule = if !(builtins.pathExists hostModulePath) then null else hostModulePath;
in
{
  imports = lib.optional (hostModule != null) hostModule;
}
