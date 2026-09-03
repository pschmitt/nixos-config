# osd — fire an ad-hoc on-screen notification.
#
# Uses DMS's native toast IPC (dms ipc call toast ...) when dms.service is
# the running bar, falling back to notify-send/mako otherwise — so scripts
# and keybinds get a native-looking OSD regardless of which bar is active
# mid-migration (see toggle-bar.sh).

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] MESSAGE...
       $(basename "$0") dismiss CATEGORY
       $(basename "$0") hide
       $(basename "$0") status

Options:
  -s, --severity {info,warn,error}   Severity (default: info)
  -c, --category CATEGORY            Dedupe/update-in-place key (DMS only;
                                      repeated calls with the same category
                                      replace the previous toast instead of
                                      stacking). Defaults to --app-name.
  -d, --details TEXT                 Extra detail line (DMS only)
  -x, --command CMD                  Command run when the toast is clicked
                                      (DMS only)
  -a, --app-name NAME                notify-send app name (fallback only,
                                      default: osd)
  -t, --timeout MS                   notify-send timeout in ms (fallback
                                      only)
  -h, --help                         Show this help
EOF
}

use_dms() {
  command -v dms &>/dev/null && dms ipc call toast status &>/dev/null
}

send() {
  local severity="$1"
  local message="$2"
  local details="$3"
  local cmd="$4"
  local category="$5"
  local app_name="$6"
  local timeout="$7"

  if use_dms
  then
    dms ipc call toast "${severity}With" "$message" "$details" "$cmd" "$category" &>/dev/null && return 0
  fi

  local -a args
  args=(--app-name "$app_name")
  [[ -n "$timeout" ]] && args+=(-t "$timeout")
  [[ -n "$category" ]] && args+=(--hint "string:x-canonical-private-synchronous:${category}")

  case "$severity" in
    error)
      args+=(--urgency critical)
      ;;
    warn)
      args+=(--urgency normal)
      ;;
    *)
      args+=(--urgency low)
      ;;
  esac

  notify-send "${args[@]}" "$message" "$details"
}

ipc_dismiss() {
  local category="$1"

  if use_dms
  then
    dms ipc call toast dismiss "$category" &>/dev/null && return 0
  fi

  command -v makoctl &>/dev/null || return 1
  command -v jq &>/dev/null || return 1

  local id rc=1
  while IFS= read -r id
  do
    [[ -n "$id" ]] || continue
    makoctl dismiss -n "$id"
    rc=0
  done < <(makoctl list 2>/dev/null | jq -er --arg n "$category" '.data[0][] | select(.["app-name"].data == $n).id.data' 2>/dev/null)

  return "$rc"
}

ipc_hide() {
  if use_dms
  then
    dms ipc call toast hide &>/dev/null && return 0
  fi

  command -v makoctl &>/dev/null || return 1
  makoctl dismiss --all
}

ipc_status() {
  if use_dms
  then
    dms ipc call toast status
    return $?
  fi

  echo "dms not running; no fallback status available" >&2
  return 1
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    dismiss)
      shift
      if [[ -z "${1:-}" ]]
      then
        printf 'Missing category\n' >&2
        usage >&2
        return 2
      fi
      ipc_dismiss "$1"
      return $?
      ;;
    hide)
      ipc_hide
      return $?
      ;;
    status)
      ipc_status
      return $?
      ;;
  esac

  local severity=info category="" details="" cmd="" app_name=osd timeout=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -s|--severity)
        severity="$2"
        shift 2
        ;;
      -c|--category)
        category="$2"
        shift 2
        ;;
      -d|--details)
        details="$2"
        shift 2
        ;;
      -x|--command)
        cmd="$2"
        shift 2
        ;;
      -a|--app-name)
        app_name="$2"
        shift 2
        ;;
      -t|--timeout)
        timeout="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -z "${1:-}" ]]
  then
    printf 'Missing message\n' >&2
    usage >&2
    return 2
  fi

  case "$severity" in
    info|warn|error)
      ;;
    *)
      printf 'Invalid severity: %s (expected info|warn|error)\n' "$severity" >&2
      return 2
      ;;
  esac

  [[ -z "$category" ]] && category="$app_name"

  send "$severity" "$*" "$details" "$cmd" "$category" "$app_name" "$timeout"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
