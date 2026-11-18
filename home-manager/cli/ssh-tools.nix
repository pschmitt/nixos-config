{ pkgs, ... }:
{
  home.packages = [
    pkgs.autossh
    pkgs.mosh
  ];
}
