{
  config,
  lib,
  pkgs,
  ...
}:
let
  plugin = pkgs.zsh-diff-so-fancy;
  inherit (import ./path.nix { inherit config lib; }) pluginPath termuxMode;
in
{
  home.packages = lib.optionals (!termuxMode) [
    pkgs.diff-so-fancy
    plugin
  ];

  programs.zsh.initContent = lib.mkOrder 1120 ''
    zsh::source-plugin ${
      pluginPath "diff-so-fancy" "zsh-diff-so-fancy.plugin.zsh"
        "${plugin}/share/zsh/plugins/zsh-diff-so-fancy/zsh-diff-so-fancy.plugin.zsh"
    } diff-so-fancy
  '';
}
