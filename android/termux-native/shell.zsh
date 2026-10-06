[[ -o interactive ]] || return 0

mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
typeset -g _native_yadm_config=${TERMUX_NATIVE_YADM_CONFIG:-0}
typeset -g _native_yadm_zdotdir="$XDG_CONFIG_HOME/zsh"

# These are the shared Home Manager Zsh integrations. In Termux mode they call
# the package-manager-provided commands instead of baking Linux store paths in.
source "$ZDOTDIR/custom/os/home-manager/system.zsh"

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
source "$TERMUX_GENERATION/home/.config/zsh/termux/prompt-color.zsh"
ZDOTDIR="$_native_profile_zdotdir"
unset _native_profile_zdotdir _native_yadm_zdotdir

# Refuse first-run daemon acquisition: our Android executable is in the bundle.
if zsh::prompt-plugins-enabled
then
  if [[ -r "$XDG_CONFIG_HOME/zsh/p10k.zsh" ]]
  then
    source "$XDG_CONFIG_HOME/zsh/p10k.zsh"
  else
    source "$TERMUX_GENERATION/shell/prompt.zsh"
  fi
fi
source "$TERMUX_GENERATION/shell/plugins/example.zsh"

if [[ "$_native_yadm_config" == 1 ]]
then
  () {
    setopt localoptions nullglob
    local plugin_file
    for plugin_file in \
      "$_native_yadm_zdotdir"/plugins/local/*.zsh(N) \
      "$_native_yadm_zdotdir"/plugins/local/work/*.zsh(N) \
      "$_native_yadm_zdotdir"/plugins/local/99-after/*.zsh(N)
    do
      [[ "${plugin_file:t}" == zinit.zsh ]] && continue
      zsh::source-plugin "$plugin_file"
    done
  }
  if [[ -r "$_native_yadm_zdotdir/zinit/completions.zsh" ]]
  then
    () {
      zzinit() { : }
      source "$_native_yadm_zdotdir/zinit/completions.zsh"
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
  if [[ "${TERMUX_RUN_MODE:-}" != ci && -r "$_native_yadm_zdotdir/secrets.zsh" ]]
  then
    source "$_native_yadm_zdotdir/secrets.zsh"
  fi
  typeset -g TERMUX_NATIVE_USER_PLUGINS_READY=1
fi
unset _native_yadm_config _native_yadm_zdotdir
# Host extensions are runtime inputs, not embedded in a public artifact.
if [[ -r "$XDG_CONFIG_HOME/termux-native/host.zsh" ]]
then
  source "$XDG_CONFIG_HOME/termux-native/host.zsh"
fi
typeset -g TERMUX_NATIVE_READY=1
true

# vim: set ft=zsh et ts=2 sw=2 :
