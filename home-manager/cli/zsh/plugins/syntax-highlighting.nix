{
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 1550 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::load-syntax-highlighting() {
        zsh::source-plugin ${lib.escapeShellArg "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"}
        ZSH_HIGHLIGHT_STYLES[comment]='fg=006'
      }
      zsh::defer zsh::load-syntax-highlighting
    fi
  '';
}
