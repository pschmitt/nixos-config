{
  lib,
  pkgs,
  ...
}:
let
  plugin = pkgs.zsh-diff-so-fancy;
in
{
  home.packages = [
    pkgs.diff-so-fancy
    plugin
  ];

  programs.zsh.initContent = lib.mkOrder 1120 ''
    zsh::source-plugin ${lib.escapeShellArg "${plugin}/share/zsh/plugins/zsh-diff-so-fancy/zsh-diff-so-fancy.plugin.zsh"} diff-so-fancy
  '';
}
