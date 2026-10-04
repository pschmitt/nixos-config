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
  home.packages = lib.optionals (!termuxMode) [
    inputs.rbw.packages.${pkgs.stdenv.hostPlatform.system}.rbw
  ];
}
