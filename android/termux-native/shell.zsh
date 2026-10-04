source "${${(%):-%N}:A:h}/.zshenv"
[[ -o interactive ]] || return 0

mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"
setopt rc_quotes
alias -g DN='&> /dev/null' L='| less' J='| jq'

# These are the shared Home Manager Zsh integrations. In Termux mode they call
# the package-manager-provided commands instead of baking Linux store paths in.
source "$ZDOTDIR/custom/os/home-manager/system.zsh"

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
