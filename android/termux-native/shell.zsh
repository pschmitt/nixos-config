[[ -o interactive ]] || return 0

mkdir -p "$XDG_CACHE_HOME/termux-native/${TERMUX_GENERATION:t}"

# This Nix-generated file defines the generation-aware nvim function.
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

  # The regular custom loader applies the Termux and host overlays after its
  # zboot files. Keep those yadm-owned files on-device and follow that order.
  [[ -r "$ZDOTDIR/custom/os/termux/zboot.zsh" ]] && source "$ZDOTDIR/custom/os/termux/zboot.zsh"
  () {
    setopt localoptions nullglob extendedglob
    multisrc \
      "$ZDOTDIR/custom/os/termux"/^zboot.zsh(N.) \
      "$ZDOTDIR/custom/hosts/$HOST"/^zboot.zsh(N.)
  }

  [[ -r "$ZDOTDIR/interactive.zsh" ]] && source "$ZDOTDIR/interactive.zsh"
  [[ -z "${NO_BS:-}" && -r "$ZDOTDIR/dirs.zsh" ]] && source "$ZDOTDIR/dirs.zsh"
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

# Host extensions are runtime inputs, not embedded in a public artifact.
if [[ -r "$XDG_CONFIG_HOME/termux-native/host.zsh" ]]
then
  source "$XDG_CONFIG_HOME/termux-native/host.zsh"
fi
typeset -g TERMUX_NATIVE_READY=1
true

# vim: set ft=zsh et ts=2 sw=2 :
