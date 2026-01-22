{ pkgs, ... }:
{
  home.packages = with pkgs; [
    go
    golangci-lint
  ];
}
