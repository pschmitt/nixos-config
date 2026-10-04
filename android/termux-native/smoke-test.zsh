native_shell_check() {
  [[ $TERMUX_NATIVE_READY == 1 ]] || return 1
  if (( $+functions[zinit] || $+aliases[zinit] ))
  then
    print -u2 -- 'Zinit manager loaded in the Nix-managed Termux shell'
    return 1
  fi
  local required
  for required in p10k _zsh_autosuggest_start _zsh_highlight history-substring-search-up \
    autopair-insert extract _atuin_search _direnv_hook __zoxide_z termux-native-status \
    prompt::simple prompt::reset
  do
    if (( ! $+functions[$required] ))
    then
      print -u2 -- "Missing shell function: $required"
      return 1
    fi
  done
  (( $+widgets[history-substring-search-up] && $+widgets[edit-command-line] && $+widgets[_atuin_search_widget] )) || return 1
  if [[ ! -r "$TERMUX_GENERATION/home/.config/atuin/config.toml" ]]
  then
    print -u2 -- 'Termux generation is missing the Atuin settings file'
    return 1
  fi
  if [[ ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_mani" ||
        ! -r "$TERMUX_GENERATION/home/.local/share/man/man1/mani.1" ]]
  then
    print -u2 -- 'Termux generation is missing the mani completion or man page'
    return 1
  fi
  local atuin_binding
  atuin_binding=$(bindkey '^[r') || return 1
  if [[ "$atuin_binding" != *'_atuin_search_widget' ]]
  then
    print -u2 -- "Alt-R is not bound to the Atuin search widget: $atuin_binding"
    return 1
  fi
  if (( ! $+_comps[git] || ! $+_comps[mani] ))
  then
    print -u2 -- "Missing completion registration: git=$+_comps[git] mani=$+_comps[mani]"
    return 1
  fi
  [[ $GITSTATUS_AUTO_INSTALL == 0 && -x $GITSTATUS_DAEMON ]] || return 1
  local command
  for command in atuin bat eza fd rg ssh-to-age tmux vivid nixpp
  do
    if [[ ${commands[$command]:-} != "$TERMUX_GENERATION/bin/$command" ]]
    then
      print -u2 -- "Nix-built Android command is not active: $command"
      return 1
    fi
  done
  if [[ ${commands[zoxide]:-} != "$PREFIX/bin/zoxide" ]]
  then
    print -u2 -- "Termux APT command is not active: zoxide"
    return 1
  fi
  if [[ ${commands[shellcheck]:-} != "$PREFIX/bin/shellcheck" ]]
  then
    print -u2 -- "Termux APT command is not active: shellcheck"
    return 1
  fi
  if (( $+commands[zinit] || $+functions[zinit] || $+aliases[zinit] ))
  then
    print -u2 -- 'Zinit manager loaded in the Nix-managed Termux shell'
    return 1
  fi
  atuin --version >/dev/null || return
  bat --version >/dev/null || return
  eza --version >/dev/null || return
  fd --version >/dev/null || return
  rg --version >/dev/null || return
  assh --help >/dev/null 2>&1 || return
  mani --help >/dev/null 2>&1 || return
  rancher --help >/dev/null 2>&1 || return
  vivid generate one-dark >/dev/null || return
  tmux -V >/dev/null || return
  zoxide --version >/dev/null || return
  shellcheck --version >/dev/null || return
  nixpp switch --help >/dev/null 2>&1 || return
  "$GITSTATUS_DAEMON" --version || return
  termux-native-status || return
  local tmux_socket="native-smoke-$$"
  tmux -L "$tmux_socket" -f /dev/null new-session -d -s native-smoke || return
  tmux -L "$tmux_socket" has-session -t native-smoke || {
    tmux -L "$tmux_socket" kill-server
    return 1
  }
  tmux -L "$tmux_socket" kill-server || return
  local fixture
  fixture=$(mktemp -d "$TMPDIR/native-gitstatus.XXXXXXXX") || return
  git init -q "$fixture" || return
  gitstatus_start NATIVE_CHECK || return
  gitstatus_query -d "$fixture" NATIVE_CHECK || return
  local result=$VCS_STATUS_RESULT
  gitstatus_stop NATIVE_CHECK
  [[ $result == ok-sync ]]
  ssh-keygen -q -t ed25519 -N '' -f "$fixture/test-key" || return
  ssh-to-age -private-key -i "$fixture/test-key" -o "$fixture/age-key" || return
  [[ -s "$fixture/age-key" && "$(head -n 1 "$fixture/age-key")" == AGE-SECRET-KEY-* ]] || return 1
}

if native_shell_check
then
  print -r -- 'TERMUX_NATIVE_SMOKE_OK: shared Zsh features, prompt controls, native tools, and no Zinit'
else
  print -u2 -r -- 'TERMUX_NATIVE_SMOKE_FAILED'
  return 1
fi

# vim: set ft=zsh et ts=2 sw=2 :
