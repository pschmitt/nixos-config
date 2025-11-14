#!/run/current-system/sw/bin/bash

# Set PATH
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:${PATH}"

# Example args: button/lid LID open
BUTTON="$1"
BUTTON_NAME="$2"
EVENT="$3"

log() {
  logger --tag hyprland "$*"
}

zhj() {
  local self
  self="$(basename "$0")"
  log "$self -> running zhj '$*'"
  ~pschmitt/bin/zhj -x "$@"
}

log "Lid event: $*"

case "$BUTTON" in
  button/lid)
    case "$BUTTON_NAME" in
      LID)
        case "$EVENT" in
          open)
            zhj 'dpms on'
            ;;
          close)
            zhj 'lockscreen::lock --now; dpms off'
            zhj 'playerctl pause'
            ;;
        esac
        ;;
    esac
    ;;
esac
