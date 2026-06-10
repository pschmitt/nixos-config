{ pkgs, ... }:
{
  home.packages = [
    pkgs.cdpcurl
    pkgs.pytr
  ];
}
