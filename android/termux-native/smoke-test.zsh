native_shell_check() {
  [[ $TERMUX_NATIVE_READY == 1 ]] || return 1
  if [[ "${TERMUX_NATIVE_YADM_CONFIG:-}" == 1 ]]
  then
    [[ "$ZDOTDIR" == "$HOME/.config/zsh" ]] || return 1
    [[ "$HISTFILE" == "$XDG_STATE_HOME/zsh/zhistory" ]] || return 1
    [[ "${TERMUX_NATIVE_USER_PLUGINS_READY:-}" == 1 ]] || return 1
  fi
  local required
  for required in p10k _zsh_autosuggest_start _zsh_highlight history-substring-search-up \
    autopair-insert extract _atuin_search _direnv_hook __zoxide_z termux-native-status
  do
    if (( ! $+functions[$required] ))
    then
      print -u2 -- "Missing shell function: $required"
      return 1
    fi
  done
  (( $+widgets[history-substring-search-up] && $+widgets[edit-command-line] && $+widgets[_atuin_search_widget] )) || return 1
  (( $+_comps[git] )) || return 1
  [[ $GITSTATUS_AUTO_INSTALL == 0 && -x $GITSTATUS_DAEMON ]] || return 1
  local command
  for command in bat eza fd rg vivid zoxide nixpp
  do
    if [[ ${commands[$command]:-} != "$TERMUX_GENERATION/bin/$command" ]]
    then
      print -u2 -- "Nix-built Android command is not active: $command"
      return 1
    fi
  done
  for command in atuin tmux
  do
    if [[ ${commands[$command]:-} != "$PREFIX/bin/$command" ]]
    then
      print -u2 -- "Termux APT command is not active: $command"
      return 1
    fi
  done
  atuin --version >/dev/null || return
  bat --version >/dev/null || return
  eza --version >/dev/null || return
  fd --version >/dev/null || return
  rg --version >/dev/null || return
  vivid generate one-dark >/dev/null || return
  tmux -V >/dev/null || return
  zoxide --version >/dev/null || return
  nixpp switch --help >/dev/null 2>&1 || return
  nixpp status --help >/dev/null 2>&1 || return
  "$GITSTATUS_DAEMON" --version || return
  termux-native-status || return
  local tmux_socket="$TMPDIR/native-smoke-$$.sock"
  tmux -S "$tmux_socket" -f /dev/null new-session -d -s native-smoke || return
  tmux -S "$tmux_socket" has-session -t native-smoke || {
    tmux -S "$tmux_socket" kill-server
    return 1
  }
  tmux -S "$tmux_socket" kill-server || return
  local fixture
  fixture=$(mktemp -d "$TMPDIR/native-gitstatus.XXXXXXXX") || return
  git init -q "$fixture" || return
  gitstatus_start NATIVE_CHECK || return
  gitstatus_query -d "$fixture" NATIVE_CHECK || return
  local result=$VCS_STATUS_RESULT
  gitstatus_stop NATIVE_CHECK
  [[ $result == ok-sync ]]
}

native_shell_check

# vim: set ft=zsh et ts=2 sw=2 :
