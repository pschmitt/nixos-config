# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Once per calendar day, open a new pane in the "main" tmux session (creating
the session if needed) and run "yup" there. Intended to run once at login,
not on a recurring timer.
EOF
}

main() {
  if [[ -n "${1:-}" ]]
  then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  local session="main"
  local marker="${XDG_STATE_HOME:-$HOME/.local/state}/yup-startup/last-run"
  local today
  today="$(date +%F)"

  if [[ -f "$marker" && "$(<"$marker")" == "$today" ]]
  then
    printf 'yup already ran today (%s), nothing to do\n' "$today"
    return 0
  fi

  if ! tmux has-session -t "$session" 2>/dev/null
  then
    tmux new-session -d -s "$session"
  fi

  local new_pane
  new_pane="$(tmux split-window -t "${session}:0" -P -F '#{pane_id}')"
  tmux send-keys -t "$new_pane" "yup" C-m

  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$today" > "$marker"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
