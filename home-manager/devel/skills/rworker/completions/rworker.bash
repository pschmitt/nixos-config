# bash completion for rworker (skills/rworker). Actions, flags and values come
# from `rworker __spec`, worker names from `rworker __workers` (the cached
# last ls, refreshed in the background), so TAB never waits on the network.

_rworker_workers() {
  rworker __workers "${COMP_WORDS[1]:-}" 2>/dev/null | cut -f1
}

_rworker() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local action="${COMP_WORDS[1]:-}"
  local spec words="" line flag
  spec=$(rworker __spec 2>/dev/null)

  if [[ $COMP_CWORD -eq 1 ]] || [[ "$action" == help && $COMP_CWORD -eq 2 ]]
  then
    words=$(sed -n 's/^action \([^ ]*\) .*/\1/p' <<< "$spec")
  elif [[ $COMP_CWORD -eq 2 && "$cur" != -* ]] && grep -q -E "^worker( .*)? ${action}( |\$)" <<< "$spec"
  then
    words=$(_rworker_workers)
  elif [[ "$action" == cp ]]
  then
    if [[ "$cur" != *:* ]]
    then
      mapfile -t COMPREPLY < <(compgen -W "$(_rworker_workers | sed 's/$/:/')" -- "$cur"; compgen -f -- "$cur")
      compopt -o nospace 2>/dev/null
    fi
    return
  elif [[ "$action" == sync && $COMP_CWORD -eq 3 ]]
  then
    mapfile -t COMPREPLY < <(compgen -d -- "$cur")
    return
  else
    # ssh --create takes up's flags.
    if [[ "$action" == ssh && "${COMP_WORDS[2]:-}" == --create ]]
    then
      action=up
    fi
    # value of the previous flag?
    while read -r line
    do
      flag="${line%% *}"
      if [[ "$flag" == "${prev}=path" ]]
      then
        mapfile -t COMPREPLY < <(compgen -f -- "$cur")
        return
      elif [[ "$flag" == "${prev}="* ]]
      then
        words=$(sed -n "s/^values ${flag#*=} //p" <<< "$spec")
        mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
        return
      fi
    done < <(sed -n "s/^flag ${action} //p" <<< "$spec")
    words="$(sed -n "s/^flag ${action} \([^ =]*\).*/\1/p" <<< "$spec") --help"
    if [[ "$action" != ssh ]]
    then
      words+=" $(sed -n 's/^global \([^ ]*\) .*/\1/p' <<< "$spec")"
    fi
  fi
  mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
}

complete -F _rworker rworker

# vim: set ft=sh et ts=2 sw=2 :
