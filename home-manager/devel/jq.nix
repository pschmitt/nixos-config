{ pkgs, ... }:
{
  home.packages = with pkgs; [
    jc
    jq
    jsonrepair
    yq-go
  ];
}
