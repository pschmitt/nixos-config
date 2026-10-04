native_check_pty() {
  local generation=$1 response
  zmodload zsh/zpty || return
  zpty native "$PREFIX/bin/zsh" -fi || return
  trap 'zpty -d native 2>/dev/null' EXIT
  zpty -w native "export TERMUX_GENERATION=${(q)generation}; export ZDOTDIR=\$TERMUX_GENERATION/home/.config/zsh; source \$ZDOTDIR/.zshenv && source \$ZDOTDIR/.zshrc && source \$TERMUX_GENERATION/shell/smoke-test.zsh; print -r -- NATIVE_TEST_DONE:\$?; exit" || return
  zpty -r native response '*NATIVE_TEST_DONE:[0-9]*' || return
  zpty -d native
  print -r -- "$response"
  [[ $response == *NATIVE_TEST_DONE:0* ]]
}

native_check_pty "$@"

# vim: set ft=zsh et ts=2 sw=2 :
