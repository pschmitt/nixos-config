native_wait_for_result() {
  local name=$1 marker=$2 response child_status='' read_status

  # Read complete PTY lines and accept only the exact nonce and numeric status suffix.
  while true
  do
    response=''
    zpty -r "$name" response
    read_status=$?
    response=${response%$'\n'}
    response=${response%$'\r'}
    if [[ -n "$response" ]]
    then
      print -r -- "$response"
      if [[ $response == *"$marker:0" ]]
      then
        child_status=0
        break
      elif [[ $response == *"$marker:1" ]]
      then
        child_status=1
        break
      fi
    fi
    (( read_status == 0 )) || break
  done

  if [[ -z "$child_status" ]]
  then
    print -u2 -r -- "PTY command exited before reporting: $marker"
    zpty -d "$name" 2>/dev/null
    return 1
  fi

  # The child exits after printing the marker; close its PTY exactly once here.
  zpty -d "$name" 2>/dev/null
  (( child_status == 0 ))
}

native_check_pty() {
  local generation=$1 nonce script
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  script="
    stty -echo
    stty rows 24 cols 80
    export TERMUX_NATIVE_GENERATION_OVERRIDE=${(q)generation}
    export TERMUX_NATIVE_ZDOTDIR=${(q)generation}/home/.config/zsh
    source ${(q)generation}/zshenv || exit 1
    source \$ZDOTDIR/.zshenv || exit 1
    if [[ -o login && -r \$ZDOTDIR/.zprofile ]]
    then
      source \$ZDOTDIR/.zprofile || exit 1
    fi
    if [[ -o interactive && -r \$ZDOTDIR/.zshrc ]]
    then
      source \$ZDOTDIR/.zshrc || exit 1
    fi
    if [[ -o login && -r \$ZDOTDIR/.zlogin ]]
    then
      source \$ZDOTDIR/.zlogin || exit 1
    fi
    source \"$generation/shell/smoke-test.zsh\"
    smoke_status=\$?
    print -r -- 'NATIVE_TEST_DONE:$nonce:'\$smoke_status
    exit \$smoke_status
  "
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
  zpty native env "${native_environment[@]}" "$PREFIX/bin/zsh" -f -l -i -c ${(q)script} || return
  trap 'zpty -d native 2>/dev/null' EXIT
  native_wait_for_result native "NATIVE_TEST_DONE:$nonce"
  local result=$?
  trap - EXIT
  return $result
}

native_check_no_plugins() {
  local generation=$1 nonce script
  local -a native_environment=(
    "NO_PLUGINS=1" \
    "TERMUX_NATIVE_GENERATION_OVERRIDE=$generation" \
    "TERMUX_NATIVE_ZDOTDIR=$generation/home/.config/zsh" \
    "TERMUX_RUN_MODE=ci" \
    "PATH=$PREFIX/bin:$generation/bin:$PATH" \
  )
  zmodload zsh/zpty || return
  nonce="${$}-${RANDOM}-${RANDOM}"
  script="
    stty -echo
    stty rows 24 cols 80
    export TERMUX_NATIVE_GENERATION_OVERRIDE=${(q)generation}
    export TERMUX_NATIVE_ZDOTDIR=${(q)generation}/home/.config/zsh
    source ${(q)generation}/zshenv || exit 1
    source \$ZDOTDIR/.zshenv || exit 1
    if [[ -o login && -r \$ZDOTDIR/.zprofile ]]
    then
      source \$ZDOTDIR/.zprofile || exit 1
    fi
    if [[ -o interactive && -r \$ZDOTDIR/.zshrc ]]
    then
      source \$ZDOTDIR/.zshrc || exit 1
    fi
    if [[ -o login && -r \$ZDOTDIR/.zlogin ]]
    then
      source \$ZDOTDIR/.zlogin || exit 1
    fi
    if (( \$+functions[zinit] || \$+aliases[zinit] || \$+commands[zinit] )); then
      print -r -- 'NO_PLUGINS_CHECK:$nonce:1'
      exit 1
    else
      print -r -- 'NO_PLUGINS_CHECK:$nonce:0'
      exit 0
    fi
  "
  if [[ -r "$HOME/.config/zsh/.zshenv" && -r "$HOME/.config/zsh/.zshrc" ]]
  then
    native_environment+=("TERMUX_NATIVE_YADM_CONFIG=1")
  fi
  zpty no-plugins env "${native_environment[@]}" \
    "$PREFIX/bin/zsh" -f -l -i -c ${(q)script} || return
  native_wait_for_result no-plugins "NO_PLUGINS_CHECK:$nonce"
}

native_check_pty "$@" && native_check_no_plugins "$@"

# vim: set ft=zsh et ts=2 sw=2 :
