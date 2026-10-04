{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./path.nix { inherit config lib; }) pluginTree;
in
{
  programs.zsh.initContent = lib.mkOrder 525 ''
    fpath=("${
      pluginTree "prezto-archive" "functions"
        "${pkgs.zsh-prezto}/share/zsh-prezto/modules/archive/functions"
    }" $fpath)
    autoload -Uz lsarchive
  '';
}
