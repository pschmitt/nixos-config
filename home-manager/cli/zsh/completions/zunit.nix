{ lib, pkgs, ... }:
{
  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=(${pkgs.zunit}/share/zsh/site-functions $fpath)
  '';
}
