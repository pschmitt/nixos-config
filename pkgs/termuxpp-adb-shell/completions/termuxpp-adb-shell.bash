_termuxpp_adb_shell() {
  local current previous serial state rest
  current="${COMP_WORDS[COMP_CWORD]}"
  previous="${COMP_WORDS[COMP_CWORD-1]}"
  COMPREPLY=()
  case "$previous" in
    --mode)
      mapfile -t COMPREPLY < <(compgen -W 'auto mtls run-as' -- "$current")
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
  mapfile -t COMPREPLY < <(compgen -W '--help --serial --mode --provision --name --credential-dir --list-authorizations --revoke --completions' -- "$current")
}
complete -F _termuxpp_adb_shell termuxpp-adb-shell termuxpp-adb-shell.py

# vim: set ft=sh et ts=2 sw=2 :
