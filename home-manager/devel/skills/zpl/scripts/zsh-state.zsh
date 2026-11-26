#!/usr/bin/env zsh
#!/usr/bin/env zsh
# Dump the state of an interactive shell for comparisons:
#   zsh-state.zsh OUT
# runs an interactive zsh (local plugins loaded synchronously) that sources
# this file. Function bodies, aliases, key bindings, zstyles, options, named
# directories, fpath, completions and parameters (volatile ones left out).
if [[ "$ZSH_EVAL_CONTEXT" != *file* ]]
then
  if [[ -z "${1:-}" || "$1" == (-h|--help) ]]
  then
    print -r -- "Usage: ${0:t} OUT"
    [[ -n "${1:-}" ]]
    exit
  fi
  ZSH_SYNC_LOCAL_PLUGINS=1 exec zsh -i -c 'source "$1" "$2"' zsh "${0:A}" "${1:A}"
fi

() {
  local out=$1 f p km
  {
    print '## functions'
    for f in ${(ok)functions}
    do
      [[ $f == (zpl::*|__zpl_*|zsh::run-local-plugin|zsh::local-plugin*|zsh::source-local-plugins|zsh::load-local-plugins) ]] && continue
      print -r -- "### $f"
      print -r -- "${functions[$f]}"
    done
    print '## aliases'
    alias -L | sort
    print '## galiases'
    alias -gL | sort
    print '## saliases'
    alias -sL | sort
    print '## bindkeys'
    for km in $(bindkey -l)
    do
      bindkey -LM $km
    done
    print '## zstyle'
    zstyle -L | sort
    print '## options'
    setopt
    print '## named'
    hash -d | sort
    print '## fpath'
    print -l -- $fpath
    print '## comps'
    for f in ${(ok)_comps}
    do
      print -r -- "$f=${_comps[$f]}"
    done
    print '## params'
    for p in ${(ok)parameters}
    do
      [[ $p == (EPOCH*|RANDOM|SECONDS|_|LINENO|TTYIDLE|ZSH_SUBSHELL|status|pipestatus|argv|func*|parameters|functions*|*aliases|commands|nameddirs|userdirs|options|history*|job*|termcap|terminfo|zsh_scheduled_events|sysparams|errnos|modules|builtins|dis_*|widgets|keymaps|reswords|patchars|__zpl_*|__zsh_local*|_comps|_services|_patcomps|_postpatcomps|_compautos|_lastcomp|signals|PPID|TTY|ZSH_EXECUTION_STRING|ZSH_ARGZERO|histchars|HISTCMD|PWD|OLDPWD|fpath|FPATH|dirstack|*_functions|SHLVL|MATCH|MBEGIN|MEND|P9K_*|_p9k_*|__p9k_*|_POWERLEVEL9K_*|_ZSH_HIGHLIGHT*|_zsh_highlight*|_ZSH_AUTOSUGGEST*|__atuin*|_ZO_*|DIRENV_*|_direnv*|ZSH_CONFIG_[UG]ID|ATUIN_SESSION|out|f|p|km) ]] && continue
      typeset -p -- $p 2>/dev/null
    done
  } >| $out 2>&1
} "$@"

# vim: set ft=zsh et ts=2 sw=2 :
