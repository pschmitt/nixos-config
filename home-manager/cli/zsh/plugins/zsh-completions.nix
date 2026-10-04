{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginTree termuxMode;
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.zsh-completions ];
  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=("${
      pluginTree "completions" "src" "${pkgs.zsh-completions}/share/zsh/site-functions"
    }" $fpath)
  '';
}
