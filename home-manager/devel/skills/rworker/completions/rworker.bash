# bash completion for rworker (skills/rworker). Worker names come from the
# local state directory, so completing does not touch the network.

_rworker_workers() {
  local state="${XDG_STATE_HOME:-$HOME/.local/state}/rworker" file
  for file in "$state"/*.json
  do
    [[ -e "$file" ]] || continue
    file="${file##*/}"
    printf '%s\n' "${file%.json}"
  done
}

_rworker() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local action="${COMP_WORDS[1]:-}"
  local words

  if [[ $COMP_CWORD -eq 1 ]]
  then
    words="up ls down extend ssh sync builder"
  else
    case "$action" in
      up)
        words="--ttl --flavor --disk --scratch"
        ;;
      ls)
        words="--all"
        ;;
      down|builder|extend|ssh|sync)
        if [[ $COMP_CWORD -eq 2 ]]
        then
          words="$(_rworker_workers)"
        elif [[ "$action" == extend ]]
        then
          words="--ttl"
        elif [[ "$action" == sync ]]
        then
          mapfile -t COMPREPLY < <(compgen -d -- "$cur")
          return
        fi
        ;;
    esac
  fi
  mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
}

complete -F _rworker rworker

# vim: set ft=sh et ts=2 sw=2 :
