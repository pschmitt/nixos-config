native_smoke_run() {
  local description=$1
  shift
  print -r -- "  Checking $description..."
  if "$@" >/dev/null
  then
    print -r -- "  Passed: $description"
    return 0
  fi
  print -u2 -- "Smoke command failed: $description"
  return 1
}

native_shell_check() {
  if [[ ${TERMUX_NATIVE_READY:-} != 1 ]]
  then
    local generated_zshrc=missing
    [[ -r "$ZDOTDIR/.zshrc" ]] && generated_zshrc=readable
    print -u2 -- "The Termux-native Zsh environment is not marked ready (ZDOTDIR=$ZDOTDIR; generated zshrc=$generated_zshrc)"
    return 1
  fi
  if [[ "${TERMUX_NATIVE_YADM_CONFIG:-}" == 1 ]]
  then
    if [[ "$ZDOTDIR" != "$TERMUX_GENERATION/home/.config/zsh" ]]
    then
      print -u2 -- 'The managed Zsh is not using its active generation config directory'
      return 1
    fi
    if [[ "$HISTFILE" != "$XDG_STATE_HOME/zsh/zhistory" ]]
    then
      print -u2 -- 'The managed Zsh history file is not under the XDG state directory'
      return 1
    fi
    if [[ "${TERMUX_NATIVE_USER_PLUGINS_READY:-}" != 1 ]]
    then
      print -u2 -- 'The yadm Termux plugin configuration did not finish loading'
      return 1
    fi
  fi
  if (( $+functions[zinit] || $+aliases[zinit] ))
  then
    print -u2 -- 'Zinit manager loaded in the Nix-managed Termux shell'
    return 1
  fi
  if (( ! $+galiases[DN] || ! $+galiases[L] || ! $+galiases[J] ))
  then
    print -u2 -- 'The Termux global aliases are not loaded'
    return 1
  fi
  local prompt_color_file="$TERMUX_GENERATION/home/.config/zsh/termux/prompt-color.zsh"
  local prompt_color_token="%F{${host_color:-}}"
  if [[ ! -r "$prompt_color_file" || -z "${host_color:-}" ||
        "${POWERLEVEL9K_CONTEXT_TEMPLATE:-}" != *"$prompt_color_token"* ]]
  then
    print -u2 -- 'The Termux prompt is not using the Nix-configured dotfiles.promptColor'
    return 1
  fi
  local required
  for required in p10k _zsh_autosuggest_start _zsh_highlight history-substring-search-up \
    autopair-insert extract _atuin_search _direnv_hook __zoxide_z termux-native-status \
    prompt::simple prompt::reset yqo os-release::value os-release::is os-release::kind \
    is_termux is_nixos is_archlinux is_postmarketos is_fedora is_ubuntu is_distrobox \
    in_flatpak not_in_vt zsh::reload zsh::get-parent-command zsh::running-in-guake \
    suf version::at-least libc::version-at-least tmux::version-at-least falias multisrc \
    source-grep _usage
  do
    if (( ! $+functions[$required] ))
    then
      print -u2 -- "Missing shell function: $required"
      return 1
    fi
  done
  if [[ "${functions[prompt::simple]}${functions[prompt::reset]}" == *zinit* ]]
  then
    print -u2 -- 'The yadm prompt controls still depend on Zinit in the native shell'
    return 1
  fi
  if [[ "${TERMUX_NATIVE_ENABLED:-}" != 1 ]]
  then
    print -u2 -- 'The native-shell compatibility flag is not enabled'
    return 1
  fi
  if (( ! $+functions[yup] || ! $+functions[yupnc] ))
  then
    print -u2 -- 'The Home Manager Termux package upgrade functions were not loaded'
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
  if (( ! $+widgets[history-substring-search-up] || ! $+widgets[edit-command-line] || ! $+widgets[_atuin_search_widget] ))
  then
    print -u2 -- 'Missing expected Zsh line editor widgets'
    return 1
  fi
  if (( ! $+_comps[jc] ))
  then
    print -u2 -- 'The jc completion function is not registered'
    return 1
  fi
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
  if [[ ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_jc" ||
        ! -r "$TERMUX_GENERATION/home/.config/zsh/completions/_mani" ||
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
  if [[ $GITSTATUS_AUTO_INSTALL != 0 || ! -x $GITSTATUS_DAEMON ]]
  then
    print -u2 -- 'Gitstatus is not using the bundled daemon'
    return 1
  fi
  local command
  for command in eget jc nixpp obs-cli rbw slack-react ssh-to-age
  do
    if [[ ${commands[$command]:-} != "$TERMUX_GENERATION/bin/$command" ]]
    then
      print -u2 -- "Nix-built Android command is not active: $command"
      return 1
    fi
  done
  for command in adb-self android-doze notify-send termux-display termux-keepalive termux-lockscreen xsel
  do
    if [[ ${commands[$command]:-} != "$TERMUX_GENERATION/bin/$command" ]]
    then
      print -u2 -- "Termux helper command is not active: $command"
      return 1
    fi
  done
  for command in atuin bat eza fd rg udocker vivid kubectl shellcheck tmux zoxide gzip unzip zip
  do
    if [[ ${commands[$command]:-} != "$PREFIX/bin/$command" ]]
    then
      print -u2 -- "Termux APT command is not active: $command"
      return 1
    fi
  done
  if (( $+commands[zinit] || $+functions[zinit] || $+aliases[zinit] ))
  then
    print -u2 -- 'Zinit manager loaded in the Nix-managed Termux shell'
    return 1
  fi
  native_smoke_run 'Atuin version' atuin --version || return
  native_smoke_run 'OBS CLI version' obs-cli --version || return
  native_smoke_run 'jc version' jc --version || return
  native_smoke_run 'Slack reaction CLI imports' env \
    "PYTHONPATH=$TERMUX_GENERATION/native/slack-react-termux/python" \
    PYTHONDONTWRITEBYTECODE=1 python -B -c \
    'import appdirs, certifi, rich, slack_react, slack_sdk' || return
  native_smoke_run 'udocker help' udocker --help || return
  if [[ "$UDOCKER_DEFAULT_EXECUTION_MODE" != P1 ||
        "$UDOCKER_USE_PROOT_EXECUTABLE" != "$PREFIX/bin/proot" ]]
  then
    print -u2 -- 'udocker is missing its Termux proot configuration'
    return 1
  fi
  if [[ ${path[1]:-} != "$TERMUX_GENERATION/bin" ||
        ${commands[jc]:-} != "$TERMUX_GENERATION/bin/jc" ]]
  then
    print -u2 -- 'Termux generation commands do not take precedence in the active shell'
    return 1
  fi
  native_smoke_run 'Zinit update shim' zinit_ask_update || return
  native_smoke_run 'bat version' bat --version || return
  native_smoke_run 'eget version' eget --version || return
  native_smoke_run 'eza version' eza --version || return
  native_smoke_run 'fd version' fd --version || return
  native_smoke_run 'ripgrep version' rg --version || return
  native_smoke_run 'assh help' assh --help || return
  native_smoke_run 'mani help' mani --help || return
  native_smoke_run 'rancher help' rancher --help || return
  native_smoke_run 'vivid theme generation' vivid generate one-dark || return
  native_smoke_run 'gzip version' gzip --version || return
  native_smoke_run 'unzip version' unzip -v || return
  native_smoke_run 'zip version' zip -v || return
  native_smoke_run 'tmux version' tmux -V || return
  native_smoke_run 'zoxide version' zoxide --version || return
  native_smoke_run 'ShellCheck version' shellcheck --version || return
  native_smoke_run 'nixpp switch help' nixpp switch --help || return
  native_smoke_run 'gitstatus daemon version' "$GITSTATUS_DAEMON" --version || return
  native_smoke_run 'Termux status helper' termux-native-status || return
  native_smoke_run 'rbw version' rbw --version || return
  native_smoke_run 'kubectl client version' kubectl version --client --output=yaml || return
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
