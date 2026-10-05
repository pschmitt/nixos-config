[[ -o interactive ]] || return 0

mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
setopt rc_quotes
alias -g DN='&> /dev/null' L='| less' J='| jq'

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

# Host extensions are runtime inputs, not embedded in a public artifact.
if [[ -r "$XDG_CONFIG_HOME/termux-native/host.zsh" ]]
then
  source "$XDG_CONFIG_HOME/termux-native/host.zsh"
fi
typeset -g TERMUX_NATIVE_READY=1
true

# vim: set ft=zsh et ts=2 sw=2 :
