{ pkgs, ... }:
{
  home.packages = with pkgs; [ shellyctl ];
}
