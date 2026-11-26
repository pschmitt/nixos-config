{
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.zsh-completions ];
  programs.zsh.initContent = lib.mkOrder 520 ''
    fpath=("${pkgs.zsh-completions}/share/zsh/site-functions" $fpath)
  '';
}
