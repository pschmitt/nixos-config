# Shared environment initializer for login, interactive and non-interactive shells.
typeset -g TERMUX_GENERATION=${${(%):-%N}:A:h:h:h:h}
export ZDOTDIR="$TERMUX_GENERATION/home/.config/zsh"
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
export PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export TMPDIR=${TMPDIR:-$PREFIX/tmp}
export EDITOR=${EDITOR:-nvim}
export VISUAL=${VISUAL:-$EDITOR}
export PAGER=${PAGER:-less}
export BROWSER=termux-open
typeset -U path
path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)
typeset -g KEYTIMEOUT=1 REPORTTIME=10
typeset -g TERMUX_NATIVE_ENABLED=1

# Keep the managed generation as the early-startup fallback, then hand off to
# the real yadm Zsh config once yadm has installed it. Source its zshenv here:
# Zsh has already selected this generated .zshenv for the current startup.
if [[ -r "$HOME/.config/zsh/zshenv" ]]
then
  export ZDOTDIR="$HOME/.config/zsh"
  typeset -g TERMUX_NATIVE_YADM_CONFIG=1
  source "$ZDOTDIR/zshenv"
  path=("$TERMUX_GENERATION/bin" "$PREFIX/bin" $path)
else
  export ZDOTDIR="$TERMUX_GENERATION/home/.config/zsh"
  unset TERMUX_NATIVE_YADM_CONFIG
fi

# vim: set ft=zsh et ts=2 sw=2 :
