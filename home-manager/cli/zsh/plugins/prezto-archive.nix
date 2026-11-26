{
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 525 ''
    fpath=("${"${pkgs.zsh-prezto}/share/zsh-prezto/modules/archive/functions"}" $fpath)
    autoload -Uz lsarchive
  '';
}
