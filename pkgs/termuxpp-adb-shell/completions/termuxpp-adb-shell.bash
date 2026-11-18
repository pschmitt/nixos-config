_termuxpp_adb_shell() {
  local current previous serial state rest i
  current="${COMP_WORDS[COMP_CWORD]}"
  previous="${COMP_WORDS[COMP_CWORD-1]}"
  COMPREPLY=()
  for ((i = 1; i < COMP_CWORD; i++))
  do
    if [[ "${COMP_WORDS[i]}" == -- ]]
    then
      if ((COMP_CWORD == i + 1))
      then
        mapfile -t COMPREPLY < <(compgen -c -- "$current")
      else
        mapfile -t COMPREPLY < <(compgen -f -- "$current")
        compopt -o filenames
      fi
      return
    fi
  done
  case "$previous" in
    --mode)
      mapfile -t COMPREPLY < <(compgen -W 'auto mtls run-as' -- "$current")
      return
      ;;
    --shell)
      mapfile -t COMPREPLY < <(compgen -W 'bash zsh fish sh' -- "$current")
      return
      ;;
    --completions)
      mapfile -t COMPREPLY < <(compgen -W 'bash zsh fish' -- "$current")
      return
      ;;
    --serial)
      while read -r serial state rest
      do
        if [[ "$state" == device && "$serial" == "$current"* ]]
        then
          COMPREPLY+=("$serial")
        fi
      done < <(adb devices 2>/dev/null)
      while read -r serial
      do
        if [[ "$serial" == "$current"* ]]
        then
          COMPREPLY+=("$serial")
        fi
      done < <("${COMP_WORDS[0]}" --list-aliases 2>/dev/null)
      return
      ;;
    --devices-config)
      mapfile -t COMPREPLY < <(compgen -f -- "$current")
      compopt -o filenames
      return
      ;;
    --credential-dir)
      mapfile -t COMPREPLY < <(compgen -d -- "$current")
      compopt -o filenames
      return
      ;;
    --name|--revoke)
      return
      ;;
  esac
  mapfile -t COMPREPLY < <(compgen -W '--help --serial --mode --outer --shell --provision --name --credential-dir --devices-config --list-aliases --list-authorizations --revoke --completions' -- "$current")
}
complete -F _termuxpp_adb_shell termuxpp-adb-shell termuxpp-adb-shell.py

# vim: set ft=sh et ts=2 sw=2 :
