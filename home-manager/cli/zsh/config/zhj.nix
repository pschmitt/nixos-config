# `zhj` (pkgs/local/zhj) for hosts whose default ZDOTDIR is the Nix-managed
# config.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.dotfiles.zsh.nixShell.default {
    home.packages = [ pkgs.zhj ];
  };
}
