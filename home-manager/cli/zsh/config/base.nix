{ config, lib, ... }:
{
  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 500 ''
      mkdir -p -- "${config.xdg.stateHome}/zsh"
      typeset -gA CUSTOM_COMPS CUSTOM_COMPS_STATIC
      autoload -Uz colors && colors
      zmodload zsh/terminfo zsh/zpty 2>/dev/null
      [[ "$COLORTERM" == (24bit|truecolor) || "''${terminfo[colors]}" -eq 16777216 ]] || zmodload zsh/nearcolor 2>/dev/null
      autoload -Uz add-zsh-hook
      autoload -Uz url-quote-magic edit-command-line bracketed-paste-magic
      zle -N self-insert url-quote-magic
      zle -N edit-command-line
      zle -N bracketed-paste bracketed-paste-magic
      autoload -Uz run-help run-help-git run-help-openssl run-help-sudo
      (( ''${+aliases[run-help]} )) && unalias run-help
      alias help=run-help
      setopt AUTO_PUSHD
      setopt PUSHD_MINUS
      setopt AUTOCD
      setopt EXTENDED_GLOB
      setopt INTERACTIVE_COMMENTS
      setopt NO_CLOBBER
      setopt AUTO_PARAM_SLASH
      setopt AUTO_REMOVE_SLASH
    '')
    (lib.mkOrder 1300 ''
      if [[ -n "''${terminfo[smkx]}" && -n "''${terminfo[rmkx]}" ]]
      then
        zle-line-init() { echoti smkx }
        zle-line-finish() { echoti rmkx }
        zle -N zle-line-init
        zle -N zle-line-finish
      fi
    '')
  ];
}
