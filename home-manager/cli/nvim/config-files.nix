{
  appName,
  lib,
}:
lib.mapAttrs' (
  name: _:
  lib.nameValuePair "${appName}/${name}" {
    source = ./config + "/${name}";
    recursive = true;
  }
) (builtins.readDir ./config)
