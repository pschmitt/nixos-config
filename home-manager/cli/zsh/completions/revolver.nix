{
  lib,
  pkgs,
  ...
}:
{
  xdg.configFile."zsh/completions/_revolver".source =
    "${pkgs.revolver}/share/zsh/site-functions/_revolver";

  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=(${pkgs.revolver}/share/zsh/site-functions $fpath)
  '';
}
