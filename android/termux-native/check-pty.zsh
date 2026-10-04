native_check_pty() {
  local generation=$1 response test_status read_status startup_command
  read_status=0
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  script="
    stty -echo
    if source \"\$TERMUX_GENERATION/shell/smoke-test.zsh\"; then
      print -r -- 'NATIVE_TEST_DONE:$nonce:0'
      exit 0
    else
      print -r -- 'NATIVE_TEST_DONE:$nonce:1'
      exit 1
    fi
  "
  zpty native env \
    "TERMUX_GENERATION=$generation" \
    "ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
    "$PREFIX/bin/zsh" -ic ${(q)script} || return
  trap 'zpty -d native 2>/dev/null' EXIT
  if [[ -r "$HOME/.config/zsh/.zshenv" && -r "$HOME/.config/zsh/.zshrc" ]]
  then
    startup_command="export TERMUX_RUN_MODE=ci; source ${(q)generation}/home/.config/zsh/.zshenv && source ${(q)HOME}/.config/zsh/.zshrc"
  else
    startup_command="export TERMUX_GENERATION=${(q)generation}; source ${(q)generation}/home/.config/zsh/.zshrc"
  fi
  zpty -w native "stty -echo; ${startup_command} && source ${(q)generation}/shell/smoke-test.zsh; _native_test_status=\$?; print -r -- NATIVE_TEST_DONE:\$_native_test_status; exit \$_native_test_status" || return
  zpty -r native response '*NATIVE_TEST_DONE:<->*' || read_status=$?
  if [[ ! $response =~ '(^|[[:space:]])NATIVE_TEST_DONE:([0-9]+)($|[[:space:]])' ]]
  then
    print -u2 -- 'PTY smoke test exited without a numeric result marker'
    return $((read_status == 0 ? 1 : read_status))
  fi
  if [[ $response == *'bad math expression'* || $response == *'command not found: zzinit'* ]]
  then
    print -u2 -- 'PTY startup emitted a native Zsh configuration error'
    print -u2 -- "$response"
    return 1
  fi
  test_status=$match[2]
  zpty -d native
  trap - EXIT
  return $test_status
}

native_check_no_plugins() {
  local generation=$1 response nonce child_status script
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  script="
    stty -echo
    if (( \$+functions[zinit] || \$+aliases[zinit] )); then
      print -r -- 'NO_PLUGINS_CHECK:$nonce:1'
      exit 1
    else
      print -r -- 'NO_PLUGINS_CHECK:$nonce:0'
      exit 0
    fi
  "
  zpty no-plugins env \
    "NO_PLUGINS=1" \
    "TERMUX_GENERATION=$generation" \
    "ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
    "$PREFIX/bin/zsh" -ic ${(q)script} || return
  trap 'zpty -d no-plugins 2>/dev/null' EXIT
  zpty -r -m no-plugins response "*NO_PLUGINS_CHECK:$nonce:[01]" || return
  zpty -d no-plugins
  print -r -- "$response"
  [[ $response =~ "NO_PLUGINS_CHECK:$nonce:([01])" ]] || return 1
  child_status=$match[1]
  (( child_status == 0 ))
}

native_check_pty "$@" && native_check_no_plugins "$@"

# vim: set ft=zsh et ts=2 sw=2 :
