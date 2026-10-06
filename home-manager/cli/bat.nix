{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  termux.packages = lib.mkIf termuxMode [ "bat" ];
  home.packages = lib.optionals (!termuxMode) [ pkgs.bat ];
}
