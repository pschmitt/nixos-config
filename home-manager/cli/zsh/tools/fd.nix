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
  home.packages = lib.optionals (!termuxMode) [ pkgs.fd ];
  programs.zsh.shellAliases.fd = "noglob fd";
}
