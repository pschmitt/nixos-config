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
  xdg.configFile."zsh/completions/_revolver".source =
    "${pkgs.revolver}/share/zsh/site-functions/_revolver";

  programs.zsh.initContent = lib.mkIf (!termuxMode) (
    lib.mkOrder 520 ''
      fpath=(${pkgs.revolver}/share/zsh/site-functions $fpath)
    ''
  );
}
