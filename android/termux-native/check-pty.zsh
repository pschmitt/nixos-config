native_wait_for_result() {
  local name=$1 marker=$2 keep_open=${3:-0}
  local response buffer='' line result child_status='' read_status

  # PTY reads can return several lines together; inspect each complete line.
  while true
  do
    response=''
    zpty -r "$name" response
    read_status=$?
    buffer+=$response
    (( read_status == 0 )) || buffer+=$'\n'

    while [[ "$buffer" == *$'\n'* ]]
    do
      line=${buffer%%$'\n'*}
      buffer=${buffer#*$'\n'}
      line=${line//$'\r'/}
      [[ -n "$line" ]] && print -r -- "$line"

      if [[ "$line" == "$marker"* ]]
      then
        result=${line#"$marker"}
        if [[ -n "$result" && "$result" != *[^0-9]* ]]
        then
          child_status=$result
          break
        fi
      fi
    done

    [[ -n "$child_status" ]] && break
    (( read_status == 0 )) || break
  done

  if [[ -z "$child_status" ]]
  then
    print -u2 -r -- "PTY command exited before reporting: $marker"
    zpty -d "$name" 2>/dev/null
    return 1
  fi

  if [[ "$keep_open" != 1 ]]
  then
    # The child exits after printing the marker; close its PTY exactly once here.
    zpty -d "$name" 2>/dev/null
  fi
  return "$child_status"
}

native_start_interactive() {
  local name=$1 nonce=$2
  shift 2
  zpty "$name" "$@" || return
  zpty -w "$name" "stty -echo; print -r -- 'NATIVE_PTY_READY:$nonce:0'"$'\n' || return
  native_wait_for_result "$name" "NATIVE_PTY_READY:$nonce:" 1
}

native_check_pty() {
  local generation=$1 nonce startup_script
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  startup_script=$(mktemp "${TMPDIR:-/tmp}/termux-native-startup.XXXXXXXX") || return
  trap 'rm -f -- "$startup_script"; zpty -d native 2>/dev/null' EXIT
  {
    print -r -- 'stty rows 24 cols 80'
    print -r -- "export TERMUX_NATIVE_GENERATION_OVERRIDE=${(q)generation}"
    print -r -- "export TERMUX_NATIVE_ZDOTDIR=${(q)generation}/home/.config/zsh"
    print -r -- "source ${(q)generation}/zshenv || exit 1"
    cat <<'EOF'
source "$ZDOTDIR/.zshenv" || exit 1
if [[ -o login && -r "$ZDOTDIR/.zprofile" ]]
then
  source "$ZDOTDIR/.zprofile" || exit 1
fi
termux-native-run-smoke() {
  precmd_functions=(${precmd_functions:#termux-native-run-smoke})
  source "${TERMUX_GENERATION}/shell/smoke-test.zsh"
  local smoke_status=$?
  print -r -- "NATIVE_TEST_DONE:NONCE:$smoke_status"
  exit "$smoke_status"
}
termux-native-smoke-after-plugins() {
  precmd_functions+=(termux-native-run-smoke)
}
typeset -ga zsh_after_local_plugins
zsh_after_local_plugins+=(termux-native-smoke-after-plugins)
if [[ -o interactive && -r "$ZDOTDIR/.zshrc" ]]
then
  source "$ZDOTDIR/.zshrc" || exit 1
fi
if [[ -o login && -r "$ZDOTDIR/.zlogin" ]]
then
  source "$ZDOTDIR/.zlogin" || exit 1
fi
EOF
  } >| "$startup_script" || return
  startup_script=${startup_script:A}
  local -a native_environment=(
    "COLUMNS=80" \
    "LINES=24" \
    "TERMUX_NATIVE_GENERATION_OVERRIDE=$generation" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_RUN_MODE=ci" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
  )
  if [[ -r "$HOME/.config/zsh/.zshenv" && -r "$HOME/.config/zsh/.zshrc" ]]
  then
    native_environment+=("TERMUX_NATIVE_YADM_CONFIG=1")
  fi
  trap 'rm -f -- "$startup_script"; zpty -d native 2>/dev/null' EXIT
  native_start_interactive native "$nonce" \
    env "${native_environment[@]}" "$PREFIX/bin/zsh" -f -l -i || return
  zpty -w native "source ${(q)startup_script}"$'\n' || return
  native_wait_for_result native 'NATIVE_TEST_DONE:NONCE:'
  local result=$?
  trap - EXIT
  rm -f -- "$startup_script"
  return $result
}

native_check_no_plugins() {
  local generation=$1 startup_script output result
  local -a native_environment=(
    "NO_PLUGINS=1" \
    "TERMUX_NATIVE_GENERATION_OVERRIDE=$generation" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_RUN_MODE=ci" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
  )
  if [[ -r "$HOME/.config/zsh/.zshenv" && -r "$HOME/.config/zsh/.zshrc" ]]
  then
    native_environment+=("TERMUX_NATIVE_YADM_CONFIG=1")
  fi
  startup_script=$(mktemp "${TMPDIR:-/tmp}/termux-native-no-plugins.XXXXXXXX") || return
  {
    print -r -- "source ${(q)generation}/zshenv || exit 1"
    cat <<'EOF'
source "$ZDOTDIR/.zshenv" || exit 1
if [[ -r "$ZDOTDIR/.zprofile" ]]
then
  source "$ZDOTDIR/.zprofile" || exit 1
fi
if [[ -r "$ZDOTDIR/.zshrc" ]]
then
  source "$ZDOTDIR/.zshrc" || exit 1
fi
if [[ -r "$ZDOTDIR/.zlogin" ]]
then
  source "$ZDOTDIR/.zlogin" || exit 1
fi
if (( $+functions[zinit] || $+aliases[zinit] || $+commands[zinit] ))
then
  print -r -- 'NO_PLUGINS_CHECK:1'
  exit 1
fi
print -r -- 'NO_PLUGINS_CHECK:0'
exit 0
EOF
  } >| "$startup_script" || return
  output=$(env "${native_environment[@]}" "$PREFIX/bin/zsh" -f -l -c "source ${(q)startup_script}" 2>&1)
  result=$?
  rm -f -- "$startup_script"
  print -r -- "$output"
  if (( result != 0 )) || ! grep -Fxq 'NO_PLUGINS_CHECK:0' <<< "$output"
  then
    print -u2 -- 'The NO_PLUGINS configuration check failed'
    return 1
  fi
}

native_check_pty "$@" && native_check_no_plugins "$@"

# vim: set ft=zsh et ts=2 sw=2 :
