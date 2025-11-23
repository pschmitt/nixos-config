{ lib, ... }:
let
  scriptsDir = ./scripts;
  scripts = lib.filterAttrs (_: type: type == "regular") (builtins.readDir scriptsDir);
  mkScriptFile = name: {
    name = ".config/hypr/bin/${name}";
    value = {
      source = scriptsDir + "/${name}";
      executable = true;
    };
  };
in
{
  # Declaratively populate ~/.config/hypr/bin with the legacy helper scripts.
  home.file = lib.mkMerge [
    (lib.listToAttrs (map mkScriptFile (builtins.attrNames scripts)))
  ];
}
