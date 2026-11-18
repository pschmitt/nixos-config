{ pkgs, ... }:
{
  home.packages = [ pkgs.eza ];
  programs.eza.package = pkgs.eza;
}
