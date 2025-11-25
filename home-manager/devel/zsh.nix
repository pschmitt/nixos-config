{ pkgs, ... }:
{
  home.packages = with pkgs; [
    revolver
    zunit
  ];
}
