{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.jq ];
  # force: replaces the links zinit's jq.zsh used to create (yadm-only hosts
  # still get them from there).
  xdg.configFile = {
    "jq/colors" = {
      source = inputs.colors-jq;
      force = true;
    };
    "jq/plib" = {
      source = inputs.plib-jq;
      force = true;
    };
  };
}
