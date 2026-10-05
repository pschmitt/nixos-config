native_wait_for_result() {
  local name=$1 marker=$2 response child_status pattern
  pattern="*${marker}:[01]"$'\r'

  # The PTY has echo disabled in the child. Match a complete result line,
  # including its carriage return, so echoed command text cannot pass as output.
  if ! zpty -r -m "$name" response "$pattern"
  then
    print -u2 -r -- "PTY command exited before reporting: $marker"
    zpty -d "$name" 2>/dev/null
    return 1
  fi

  if [[ $response == *"${marker}:0"$'\r' ]]
  then
    child_status=0
  elif [[ $response == *"${marker}:1"$'\r' ]]
  then
    child_status=1
  else
    print -u2 -r -- "PTY output did not end with a numeric result: $marker"
    zpty -d "$name" 2>/dev/null
    return 1
  fi

  # The interactive `zsh -i -c` child returns to a prompt after the marker.
  # The marker carries the check's status; close its PTY exactly once here.
  zpty -d "$name" 2>/dev/null
  print -r -- "$response"
  (( child_status == 0 ))
}

native_check_pty() {
  local generation=$1 nonce script
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  script="
    stty -echo
    if source \"\$TERMUX_GENERATION/shell/smoke-test.zsh\"; then
      print -r -- 'NATIVE_TEST_DONE:$nonce:0'
    else
      print -r -- 'NATIVE_TEST_DONE:$nonce:1'
    fi
  "
  zpty native env \
    "TERMUX_GENERATION=$generation" \
    "ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
    "$PREFIX/bin/zsh" -ic ${(q)script} || return
  native_wait_for_result native "NATIVE_TEST_DONE:$nonce"
}

native_check_no_plugins() {
  local generation=$1 nonce script
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  script="
    stty -echo
    if (( \$+functions[zinit] || \$+aliases[zinit] )); then
      print -r -- 'NO_PLUGINS_CHECK:$nonce:1'
    else
      print -r -- 'NO_PLUGINS_CHECK:$nonce:0'
    fi
  "
  zpty no-plugins env \
    "NO_PLUGINS=1" \
    "TERMUX_GENERATION=$generation" \
    "ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
    "$PREFIX/bin/zsh" -ic ${(q)script} || return
  native_wait_for_result no-plugins "NO_PLUGINS_CHECK:$nonce"
}

native_check_pty "$@" && native_check_no_plugins "$@"

# vim: set ft=zsh et ts=2 sw=2 :
