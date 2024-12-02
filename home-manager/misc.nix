{ pkgs, ... }:
{
  home.packages = [
    pkgs.eget
    pkgs.home-assistant-cli
  ];
}
