{
  config,
  inputs,
  lib,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  aliasTips = inputs.alias-tips;
  aliasTipsPlugin =
    if termuxMode then
      ''"$TERMUX_GENERATION/shell/plugins/alias-tips/alias-tips.plugin.zsh"''
    else
      lib.escapeShellArg "${aliasTips}/alias-tips.plugin.zsh";
in
{
  programs.zsh.initContent = lib.mkOrder 1500 ''
    zsh::apply-plugin-overrides() {
      prompt::simple() {
        if (( $+functions[p10k] ))
        then
          p10k display '*/(left|right)/*=hide'
          p10k display '*/left/prompt_char=show'
        fi

        if (( $+functions[_alias_tips__preexec] ))
        then
          autoload -Uz add-zsh-hook
          add-zsh-hook -D preexec '*alias*tips*'
        fi
      }

      prompt::reset() {
        if (( $+functions[p10k] ))
        then
          p10k display '*/(left|right)/*=show'
        fi

        if (( ! $+functions[_alias_tips__preexec] ))
        then
          zsh::source-plugin ${aliasTipsPlugin}
        else
          autoload -Uz add-zsh-hook
          add-zsh-hook preexec _alias_tips__preexec
        fi
      }
    }

    zsh::apply-plugin-overrides
  '';
}
