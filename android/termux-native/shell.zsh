[[ -o interactive ]] || return 0

typeset -g _native_yadm_config=${TERMUX_NATIVE_YADM_CONFIG:-0}
mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
setopt rc_quotes
alias -g DN='&> /dev/null' L='| less' J='| jq'

# These are the shared Home Manager Zsh integrations. In Termux mode they call
# the package-manager-provided commands instead of baking Linux store paths in.
source "$TERMUX_GENERATION/home/.config/zsh/custom/os/home-manager/system.zsh"

# Reuse selected yadm startup files as runtime inputs. Keep them in the user's
# home; none of these private files are copied into the public bundle.
typeset -g _native_profile_zdotdir="$ZDOTDIR"
typeset -g _native_yadm_zdotdir="$XDG_CONFIG_HOME/zsh"
if [[ -d "$_native_yadm_zdotdir" ]]
then
  ZDOTDIR="$_native_yadm_zdotdir"

  [[ -r "$ZDOTDIR/aliases.zsh" ]] && source "$ZDOTDIR/aliases.zsh"
  [[ -r "$ZDOTDIR/lib.zsh" ]] && source "$ZDOTDIR/lib.zsh"

  # The regular startup's traps.zsh reloads Zinit, so the native shell keeps
  # the Home Manager runtime hooks and reuses only these portable snippets.
  [[ -r "$ZDOTDIR/custom/os/termux/zboot.zsh" ]] && source "$ZDOTDIR/custom/os/termux/zboot.zsh"
  [[ -r "$ZDOTDIR/custom/os/termux/aliases.zsh" ]] && source "$ZDOTDIR/custom/os/termux/aliases.zsh"
  if [[ -n "$HOST" && -r "$ZDOTDIR/custom/hosts/$HOST/zprompt" ]]
  then
    source "$ZDOTDIR/custom/hosts/$HOST/zprompt"
  fi

  [[ -r "$ZDOTDIR/interactive.zsh" ]] && source "$ZDOTDIR/interactive.zsh"
  [[ -r "$ZDOTDIR/dirs.zsh" ]] && source "$ZDOTDIR/dirs.zsh"
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
