[[ -o interactive ]] || return 0

typeset -g _native_yadm_config=${TERMUX_NATIVE_YADM_CONFIG:-0}
mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
setopt rc_quotes
alias -g DN='&> /dev/null' L='| less' J='| jq'

# These are the shared Home Manager Zsh integrations. In Termux mode they call
# the package-manager-provided commands instead of baking Linux store paths in.
source "$TERMUX_GENERATION/home/.config/zsh/custom/os/home-manager/system.zsh"

# Initialize tools installed in the Termux prefix. Generate their shell hooks
# from the binaries active on this device so no Linux store paths enter the
# exported configuration.
# Atuin deliberately shares this timestamp between its preexec and precmd hooks.
typeset -g __atuin_preexec_time
eval "$(atuin init --disable-ctrl-r --disable-up-arrow zsh)"
eval "$(direnv hook zsh)"
export DIRENV_LOG_FORMAT=
eval "$(zoxide init zsh --no-cmd)"
eval "$(fzf --zsh)"
alias z=__zoxide_z
alias zz=__zoxide_zi
export LS_COLORS="$(vivid generate catppuccin-mocha)"
zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"

# Reuse yadm's Termux host bootstrap as a runtime input. The yadm files remain
# in the user's home and are never copied into the public bundle.
typeset -g _native_profile_zdotdir="$ZDOTDIR"
typeset -g _native_yadm_zdotdir="$XDG_CONFIG_HOME/zsh"
if [[ -r "$_native_yadm_zdotdir/custom/os/termux/zboot.zsh" ]]
then
  ZDOTDIR="$_native_yadm_zdotdir"
  source "$ZDOTDIR/custom/os/termux/zboot.zsh"
  if [[ -n "$HOST" && -r "$ZDOTDIR/custom/hosts/$HOST/zprompt" ]]
  then
    source "$ZDOTDIR/custom/hosts/$HOST/zprompt"
  fi
fi
ZDOTDIR="$_native_profile_zdotdir"
unset _native_profile_zdotdir _native_yadm_zdotdir

# Refuse first-run daemon acquisition: our Android executable is in the bundle.
typeset -g GITSTATUS_DAEMON="$TERMUX_GENERATION/bin/gitstatusd"
typeset -g GITSTATUS_AUTO_INSTALL=0
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source "$_native_plugins/powerlevel10k/gitstatus/gitstatus.plugin.zsh"
if [[ "${TERMUX_NATIVE_YADM_CONFIG:-}" == 1 && -r "$ZDOTDIR/p10k.zsh" ]]
then
  source "$ZDOTDIR/p10k.zsh"
else
  source "$TERMUX_GENERATION/shell/prompt.zsh"
fi

if zsh::prompt-plugins-enabled && not_in_vt
then
  source "$_native_plugins/autosuggestions/zsh-autosuggestions.zsh"
  typeset -g ZSH_AUTOSUGGEST_MANUAL_REBIND=1 ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
  typeset -ga ZSH_AUTOSUGGEST_STRATEGY=(match_prev_cmd history completion)
  _zsh_autosuggest_start
fi
source "$TERMUX_GENERATION/shell/plugins/example.zsh"

if [[ "$_native_yadm_config" == 1 ]]
then
  () {
    setopt localoptions nullglob
    multisrc \
      "$ZDOTDIR"/plugins/local/*.zsh \
      "$ZDOTDIR"/plugins/local/work/*.zsh \
      "$ZDOTDIR"/plugins/local/99-after/*.zsh
  }
  if [[ -r "$ZDOTDIR/zinit/completions.zsh" ]]
  then
    () {
      zzinit() { : }
      source "$ZDOTDIR/zinit/completions.zsh"
      unfunction zzinit

      local completion_pattern completion_file
      for completion_pattern in "${COMPS_TO_SOURCE[@]}"
      do
        for completion_file in ${(e)~completion_pattern}
        do
          [[ -r "$completion_file" ]] && source "$completion_file"
        done
      done
      __init_custom_completions
    }
  fi
  if [[ "${TERMUX_RUN_MODE:-}" != ci && -r "$ZDOTDIR/secrets.zsh" ]]
  then
    source "$ZDOTDIR/secrets.zsh"
  fi
  typeset -g TERMUX_NATIVE_USER_PLUGINS_READY=1
fi

# Host extensions are runtime inputs, not embedded in a public artifact.
if [[ -r "$XDG_CONFIG_HOME/termux-native/host.zsh" ]]
then
  source "$XDG_CONFIG_HOME/termux-native/host.zsh"
fi
unset _native_plugins
unset _native_yadm_config

# Zinit integrations may rewrite PATH while loading plugins. Restore the
# selected generation and Termux package directories after those changes so
# bundled commands such as nixpp stay available in the interactive shell.
path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)

typeset -g TERMUX_NATIVE_READY=1
true

# vim: set ft=zsh et ts=2 sw=2 :
