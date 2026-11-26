{
  lib,
  pkgs,
  ...
}:
{
  programs.zsh.initContent = lib.mkOrder 940 ''
    if zsh::prompt-plugins-enabled && not_in_vt
    then
      zsh::load-autosuggestions() {
        zsh::source-plugin ${lib.escapeShellArg "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"}
        export ZSH_AUTOSUGGEST_MANUAL_REBIND=1 ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
        ZSH_AUTOSUGGEST_STRATEGY=(match_prev_cmd history completion)
        _zsh_autosuggest_start
      }
      zsh::defer zsh::load-autosuggestions
    fi
  '';
}
