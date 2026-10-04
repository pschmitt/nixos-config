{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ inputs.tmux-slay.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  programs.zsh.shellAliases.tslay = lib.mkDefault "tmux-slay";
}
