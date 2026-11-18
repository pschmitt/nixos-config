{ pkgs, ... }:
{
  home.packages = [
    pkgs.alejandra
    pkgs.nixfmt
    pkgs.statix
  ];
}
