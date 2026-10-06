native_check_pty() {
  local generation=$1 response test_status read_status startup_command
  read_status=0
  zmodload zsh/zpty || return
  zpty native "$PREFIX/bin/zsh" -fi || return
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

native_check_pty "$@"

# vim: set ft=zsh et ts=2 sw=2 :
