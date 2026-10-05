native_shell_check() {
  [[ $TERMUX_NATIVE_READY == 1 ]] || return 1
  if [[ "${TERMUX_NATIVE_YADM_CONFIG:-}" == 1 ]]
  then
    [[ "$ZDOTDIR" == "$HOME/.config/zsh" ]] || return 1
    [[ "$HISTFILE" == "$XDG_STATE_HOME/zsh/zhistory" ]] || return 1
    [[ "${TERMUX_NATIVE_USER_PLUGINS_READY:-}" == 1 ]] || return 1
  fi
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
  if (( ! $+aliases[yup] || ! $+aliases[yupnc] ))
  then
    print -u2 -- 'The yadm Termux package upgrade aliases were not loaded'
    return 1
  fi
  if (( ! $+functions[__chpwd-osc7-pwd] ))
  then
    print -u2 -- 'The shared OSC 7 Zsh hook was not loaded'
    return 1
  fi
  local hook hook_count=0
  for hook in $chpwd_functions
  do
    [[ "$hook" == __chpwd-osc7-pwd ]] && (( hook_count += 1 ))
  done
  if (( hook_count != 1 ))
  then
    print -u2 -- "The OSC 7 Zsh hook is registered $hook_count times"
    return 1
  fi
  if NO_PLUGINS=1 zsh::prompt-plugins-enabled ||
    NO_PROMPT_PLUGINS=1 zsh::prompt-plugins-enabled ||
    ZINIT_SKIP_PROMPT_PLUGINS=1 zsh::prompt-plugins-enabled
  then
    print -u2 -- 'A prompt-plugin skip flag did not disable prompt plugins'
    return 1
  fi
  (( $+widgets[history-substring-search-up] && $+widgets[edit-command-line] && $+widgets[_atuin_search_widget] )) || return 1
  if [[ ! -r "$TERMUX_GENERATION/home/.config/atuin/config.toml" ]]
  then
    print -u2 -- 'Termux generation is missing the Atuin settings file'
    return 1
  fi
  if [[ ! -d "$TERMUX_GENERATION/home/.config/jq/colors" ||
        ! -d "$TERMUX_GENERATION/home/.config/jq/plib" ||
        ${aliases[fd]:-} != 'noglob fd' ]]
  then
    print -u2 -- 'Termux generation is missing shared jq configuration or the fd alias'
    return 1
  fi
  if [[ ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_mani" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_ipmi" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_ossh" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_revolver" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_rbw" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/source-me.zsh" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_whatsmy" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_zunit" ||
        ! -r "$TERMUX_GENERATION/home/.local/share/man/man1/mani.1" ]]
  then
    print -u2 -- 'Termux generation is missing shared completion config or the mani man page'
    return 1
  fi
  local atuin_binding
  atuin_binding=$(bindkey '^[r') || return 1
  if [[ "$atuin_binding" != *'_atuin_search_widget' ]]
  then
    print -u2 -- "Alt-R is not bound to the Atuin search widget: $atuin_binding"
    return 1
  fi
  if (( ! $+_comps[git] || ! $+_comps[ipmi] || ! $+_comps[kubectl] ||
        ! $+_comps[mani] || ! $+_comps[ossh] || ! $+_comps[rbw] ||
        ! $+_comps[revolver] || ! $+_comps[whatsmy] || ! $+_comps[zunit] ))
  then
    print -u2 -- "Missing shared completion registration: ipmi=$+_comps[ipmi] ossh=$+_comps[ossh] revolver=$+_comps[revolver] whatsmy=$+_comps[whatsmy] zunit=$+_comps[zunit]"
    return 1
  fi
  if (( $+commands[kubectl] && $+CUSTOM_COMPS[k] && ! $+_comps[k] ))
  then
    print -u2 -- 'A kubectl custom completion was declared but not registered'
    return 1
  fi
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
  eget --version >/dev/null || return
  eza --version >/dev/null || return
  fd --version >/dev/null || return
  rg --version >/dev/null || return
  assh --help >/dev/null 2>&1 || return
  mani --help >/dev/null 2>&1 || return
  rancher --help >/dev/null 2>&1 || return
  vivid generate one-dark >/dev/null || return
  gzip --version >/dev/null || return
  unzip -v >/dev/null || return
  zip -v >/dev/null || return
  tmux -V >/dev/null || return
  zoxide --version >/dev/null || return
  shellcheck --version >/dev/null || return
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
