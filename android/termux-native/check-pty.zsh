native_check_pty() {
  local generation=$1 response test_status
  zmodload zsh/zpty || return
  zpty native "$PREFIX/bin/zsh" -fi || return
  trap 'zpty -d native 2>/dev/null' EXIT
  zpty -w native "export TERMUX_GENERATION=${(q)generation}; source ${(q)generation}/home/.config/zsh/.zshrc && source ${(q)generation}/shell/smoke-test.zsh; _native_test_status=\$?; print -r -- NATIVE_TEST_DONE:\$_native_test_status; exit \$_native_test_status" || return
  # The echoed input contains a variable expansion, not a numeric result marker.
  zpty -r native response '*NATIVE_TEST_DONE:<->*' || return
  if [[ ! $response =~ 'NATIVE_TEST_DONE:([0-9]+)' ]]
  then
    print -u2 -- 'PTY smoke test exited without a numeric result marker'
    return 1
  fi
  test_status=$match[1]
  zpty -d native
  trap - EXIT
  return $test_status
}

native_check_pty "$@"

# vim: set ft=zsh et ts=2 sw=2 :
