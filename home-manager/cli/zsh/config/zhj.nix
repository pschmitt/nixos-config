# `zhj` (pkgs/local/zhj) for hosts whose default shell config is the
# Nix-managed one. It loads this config's ZDOTDIR (programs.zsh.dotDir).
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.dotfiles.zsh.nixShell.default {
    home.packages = [ (pkgs.zhj.override { inherit (config.programs.zsh) dotDir; }) ];
  };
}
