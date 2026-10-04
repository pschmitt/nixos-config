{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  xdg.configFile."zsh/completions/_zunit".source = "${pkgs.zunit}/share/zsh/site-functions/_zunit";

  programs.zsh.initContent = lib.mkIf (!termuxMode) (
    lib.mkOrder 520 ''
      fpath=(${pkgs.zunit}/share/zsh/site-functions $fpath)
    ''
  );
}
