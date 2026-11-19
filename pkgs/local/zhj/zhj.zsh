#  ╔══════════════════════════════════════════════════════════════════╗
#  ║                                                                  ║
#  ║        ███████╗ ██╗  ██╗      ██╗                                ║
#  ║        ╚══███╔╝ ██║  ██║      ██║    ┌──────────────────────┐    ║
#  ║          ███╔╝  ███████║      ██║    │  $ zhj your::thing   │    ║
#  ║         ███╔╝   ██╔══██║ ██   ██║    │  ✓ done. no prompt,  │    ║
#  ║        ███████╗ ██║  ██║ ╚█████╔╝    │    no fuss.          │    ║
#  ║        ╚══════╝ ╚═╝  ╚═╝  ╚════╝     └──────────────────────┘    ║
#  ║                                                                  ║
#  ║               ~~~  zhj - zee handjob  ~~~                        ║
#  ║                                                                  ║
#  ╚══════════════════════════════════════════════════════════════════╝
#
# Nix-managed counterpart of the yadm zhjrc: run a function, alias, script or
# command string with the Nix zsh config loaded (no prompt, plugins or
# completions). Usage: zhj [-x] [-e VAR=value]... [--] CMD|FILE [ARGS...]

local -a void DEBUG zhjenv
zparseopts -D -K -- c=void {x,-debug}=DEBUG
zparseopts -D -K -a zhjenv -- {e,-env}+:
zhjenv=(${zhjenv:#-e})
zhjenv=(${zhjenv:#--env})
[[ "$1" == "--" ]] && shift

# Only ZHJ is exported; NO_* must not leak into shells zhj spawns (tmux).
export ZHJ=1
NO_COMPLETIONS=1 NO_PLUGINS=1
source "$ZDOTDIR/.zshenv"
source "$ZDOTDIR/.zshrc"
zsh::source-local-plugins

() {
  local e
  for e in $zhjenv
  do
    export $e
  done
}

[[ -n "$DEBUG" ]] && set -x

if [[ "$#" -ge 1 && -e "$1" ]]
then
  ZHJ_MODE=shebang source "$@"
elif [[ "$#" -gt 0 ]]
then
  export ZHJ_MODE="eval"
  if [[ $# -eq 1 ]]
  then
    eval "$@"
  else
    "$@"
  fi
elif [[ ! -t 0 ]]
then
  eval "$(cat)"
fi
