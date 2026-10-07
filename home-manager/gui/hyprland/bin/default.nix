{ lib, pkgs, ... }:
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

  # `hyprprop` on PATH (the zsh plugin's hyprctl::prop alias).
  home.packages = [
    (pkgs.runCommand "hyprprop" { } ''
      install -Dm755 ${scriptsDir + "/hyprprop.sh"} "$out/bin/hyprprop"
    '')
  ];
}
