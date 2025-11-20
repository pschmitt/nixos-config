{
  lib,
  osConfig ? null,
  ...
}:
let
  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
  hostModules = {
    gk4 = ./host-specific/gk4.nix;
  };
  hostModule = if hostName == null then null else lib.attrByPath [ hostName ] null hostModules;
in
{
  imports = lib.optional (hostModule != null) hostModule;
}
