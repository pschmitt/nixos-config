#compdef termuxpp-adb-shell termuxpp-adb-shell.py

_termuxpp_adb_shell_serials() {
  local serial state rest
  local -a serials
  while read -r serial state rest
  do
    if [[ "$state" == device ]]
    then
      serials+=("$serial")
    fi
  done < <(adb devices 2>/dev/null)
  compadd -- "${serials[@]}"
}

_termuxpp_adb_shell() {
  _arguments -S \
    '(-h --help)'{-h,--help}'[show help]' \
    '--serial[ADB device serial]:serial:_termuxpp_adb_shell_serials' \
    '--mode[shell transport]:mode:(auto mtls run-as)' \
    '--shell[override configured login shell]:shell:(bash zsh fish sh)' \
    '--completions[print shell integration]:shell:(bash zsh fish)' \
    '(--list-authorizations --revoke)--provision[enroll mTLS client]' \
    '(--provision --revoke)--list-authorizations[list approved certificates]' \
    '(--provision --list-authorizations)--revoke[revoke approved certificate]:SHA256:' \
    '--name[client display name]:name:' \
    '--credential-dir[private mTLS credential directory]:directory:_directories' \
    '*::command:_normal'
}

compdef _termuxpp_adb_shell termuxpp-adb-shell termuxpp-adb-shell.py

if [[ "${funcstack[1]}" == _termuxpp-adb-shell ]]
then
  _termuxpp_adb_shell "$@"
fi

# vim: set ft=zsh et ts=2 sw=2 :
