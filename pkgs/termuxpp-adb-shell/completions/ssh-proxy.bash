_termuxpp_adb_ssh_proxy() {
  local current=${COMP_WORDS[COMP_CWORD]} previous=${COMP_WORDS[COMP_CWORD-1]} serial
  COMPREPLY=()
  case "$previous" in
    --serial)
      while IFS= read -r serial
      do
        [[ $serial == "$current"* ]] && COMPREPLY+=("$serial")
      done < <(termuxpp-adb-shell --list-aliases 2>/dev/null)
      ;;
    --devices-config) compopt -o filenames; mapfile -t COMPREPLY < <(compgen -f -- "$current");;
    --credential-dir) compopt -o filenames; mapfile -t COMPREPLY < <(compgen -d -- "$current");;
    --port|--probe-timeout|--start-timeout|--ready-timeout) ;;
    *)
      mapfile -t COMPREPLY < <(compgen -W '--help --serial --devices-config --port --credential-dir --no-start --probe-timeout --start-timeout --ready-timeout' -- "$current")
      ;;
  esac
}
complete -F _termuxpp_adb_ssh_proxy termuxpp-adb-ssh-proxy
# vim: set sw=2 sts=2 et:
