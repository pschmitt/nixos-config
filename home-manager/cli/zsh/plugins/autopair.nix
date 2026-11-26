{
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 950 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::source-plugin ${lib.escapeShellArg "${pkgs.zsh-autopair}/share/zsh/zsh-autopair/autopair.zsh"}
      bindkey -- '^H' backward-kill-word
    fi
  '';
}
