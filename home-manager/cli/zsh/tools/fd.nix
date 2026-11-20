{ pkgs, ... }:
{
  home.packages = [ pkgs.fd ];
  programs.zsh.shellAliases.fd = "noglob fd";
}
