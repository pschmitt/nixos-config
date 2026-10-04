{ lib, pkgs, ... }:
{
  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=(${pkgs.revolver}/share/zsh/site-functions $fpath)
  '';
}
