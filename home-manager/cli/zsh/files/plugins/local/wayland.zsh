if (( ! $+commands[wl-copy] ))
then
  return
fi

alias wl-paste="wl-paste --no-newline"
alias wlpaste="wl-paste --no-newline"
alias wlcopy="wl-copy -n"

zsh::autoload-dir wayland

alias wdspv="wayland::export-display"

# wrdr() {
#   wayland::export-display
#   case "$host" in
#     ge2)
#       wlr-randr --output
#       ;;
#   esac
# }
