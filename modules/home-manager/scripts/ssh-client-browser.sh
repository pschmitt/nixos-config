# Open URLs in the browser of the machine the user is sitting at, instead
# of on this (headless) host: ssh to the IP of the attached tmux client (or
# of the current SSH session) and run its $BROWSER there. Without a remote
# client, fall back to a local browser.

client_ip() {
  if [[ -n "${TMUX_CLIENT_IP:-}" ]]
  then
    printf '%s\n' "$TMUX_CLIENT_IP"
    return 0
  fi

  local pid conn
  if [[ -n "${TMUX:-}" ]]
  then
    # Most recently active client of this pane's session first. The tmux
    # client process inherited the environment of the SSH login it runs in.
    while read -r _ pid
    do
      conn=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null |
        sed -n 's/^SSH_CONNECTION=//p' | head -n1) || true
      if [[ -n "$conn" ]]
      then
        printf '%s\n' "${conn%% *}"
        return 0
      fi
    done < <(
      tmux list-clients -t "${TMUX_PANE:-}" \
        -F '#{client_activity} #{client_pid}' 2>/dev/null |
        sort -rn
    )
    return 1
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]
  then
    printf '%s\n' "${SSH_CONNECTION%% *}"
    return 0
  fi
  return 1
}

# Runs in the client's shell: its own $BROWSER (set by zshenv), xdg-open as
# a fallback, and a Wayland socket guess since ssh sessions have no display.
# shellcheck disable=SC2016
remote_script='
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]
then
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export XDG_RUNTIME_DIR
  for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*
  do
    case "$s" in *.lock) continue ;; esac
    [ -S "$s" ] && export WAYLAND_DISPLAY="${s##*/}" && break
  done
fi
exec "${BROWSER:-xdg-open}" "$@"
'

main() {
  if (($# == 0))
  then
    printf 'Usage: %s URL...\n' "${0##*/}" >&2
    return 2
  fi

  local ip
  if ip=$(client_ip) && [[ -n "$ip" ]]
  then
    local -a quoted=()
    local arg
    for arg in "$@"
    do
      quoted+=("$(printf '%q' "$arg")")
    done
    if printf '%s\n' "$remote_script" |
      ssh -o BatchMode=yes -o ConnectTimeout=5 "$ip" -- \
        "sh -s -- ${quoted[*]}"
    then
      return 0
    fi
    printf 'ssh-client-browser: opening on %s failed, using local browser\n' \
      "$ip" >&2
  fi

  exec "${SSH_CLIENT_BROWSER_FALLBACK:-firefox}" "$@"
}

main "$@"
