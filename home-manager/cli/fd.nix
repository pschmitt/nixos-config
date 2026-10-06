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
  termux.packages = lib.mkIf termuxMode [ "fd" ];
  home.packages = lib.optionals (!termuxMode) [ pkgs.fd ];
}
