
CMD_FALLBACK="pinentry-curses"

if [[ -z "$SSH_TTY" ]]
then
  case "$XDG_CURRENT_DESKTOP" in
    *kde*|*plasma*)
      CMD="pinentry-qt"
      ;;
    *gnome*|*sway*|Hypr*)
      CMD="pinentry-gnome3"
      ;;
  esac

  if ! command -v "$CMD" &>/dev/null
  then
    CMD="$CMD_FALLBACK"
  fi
fi

exec "${CMD:-${CMD_FALLBACK}}" "$@"
