# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Once per calendar day, open a new pane in the "main" tmux session and run
the update-and-deploy script there. Intended to run once at login, not on a
recurring timer.
EOF
}

# Wait for the "main" session rather than creating it ourselves: at login
# this can race the autostart entry that owns creating it (tmuxAttach in
# autostart.nix), and losing that race leaves us splitting into a session
# that's about to be torn down along with the rest of the early tmux server.
wait_for_session() {
  local session="$1"
  local tries=60

  while (( tries-- > 0 ))
  do
    tmux has-session -t "$session" 2>/dev/null && return 0
    sleep 1
  done

  return 1
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

  if ! wait_for_session "$session"
  then
    printf '%s session never appeared, giving up\n' "$session" >&2
    return 1
  fi

  local new_pane
  new_pane="$(tmux split-window -t "${session}:0" -P -F '#{pane_id}')"
  tmux send-keys -t "$new_pane" "/etc/nixos/scripts/update-and-deploy.sh" C-m

  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$today" > "$marker"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
