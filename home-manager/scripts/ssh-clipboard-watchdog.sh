#!/usr/bin/env bash

# Restart ssh-clipboard when it still owns the X11 clipboard but stopped
# answering selection requests (e.g. after MaximumRequestLengthExceeded on
# a large image), which makes every clipboard reader hang forever.

PROBE_TIMEOUT="${PROBE_TIMEOUT:-5}"
SERVICE="${SERVICE:-ssh-clipboard.service}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Probe the X11 clipboard and restart $SERVICE when its owner hangs.

Options:
  -h, --help    Display this message.
EOF
}

clipboard_hangs() {
  local rc=0
  timeout "$PROBE_TIMEOUT" \
    xclip -selection clipboard -target TARGETS -out >/dev/null 2>&1 || rc=$?
  # An empty clipboard fails immediately; only a timeout means a hung owner
  [[ "$rc" -eq 124 ]]
}

kill_stuck_readers() {
  # Readers started before the restart wait forever on the old owner; leave
  # `xclip -in` alone, it may be serving a fresh wl-copy selection
  pkill -u "$(id -u)" -f '^xclip .*-(o|out)$' 2>/dev/null || true
}

main() {
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        usage >&2
        return 2
        ;;
    esac
  done

  if ! clipboard_hangs
  then
    return 0
  fi

  printf 'Clipboard owner did not answer within %ss, restarting %s\n' \
    "$PROBE_TIMEOUT" "$SERVICE" >&2
  systemctl --user restart "$SERVICE"
  kill_stuck_readers
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
