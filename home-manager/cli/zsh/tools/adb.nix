{ pkgs, ... }:
{
  home.packages = [
    pkgs.adb-sh
    pkgs.android-tools
    pkgs.adb-completions
  ];
  programs.zsh.initContent = ''
    fpath=("${pkgs.adb-completions}/share/zsh/site-functions" $fpath)
  '';
}
