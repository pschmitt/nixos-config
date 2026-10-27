# Show a native Noctalia OSD, falling back to a desktop notification.
: "${WAYLAND_DISPLAY:=wayland-1}"
export WAYLAND_DISPLAY

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] MESSAGE...
       $(basename "$0") native TYPE [VALUE]

Options:
  -i, --icon GLYPH        Noctalia glyph (default: info-circle)
  -s, --severity LEVEL    info, warn, or error
  -d, --details TEXT      Append detail to the message
  -a, --app-name NAME     Notification fallback app name
  -c, --category NAME     Notification fallback replacement key
  -t, --timeout MS        Notification fallback timeout
  --inactive              Use the inactive appearance
  --progress VALUE        Progress from 0 to 1
  -h, --help              Show this help

Native types: volume, mic-volume, brightness. Values are percentages;
mic-volume also accepts muted and unmuted for the voice chain.
EOF
}

use_noctalia() {
  command -v noctalia &>/dev/null && noctalia msg status &>/dev/null
}

native_osd() {
  local kind="${1:-}"
  shift || true
  case "$kind" in
    volume|mic-volume) ;;
    brightness)
      if [[ $# -eq 0 ]]
      then
        printf 'Missing percentage for %s\n' "$kind" >&2
        return 2
      fi
      ;;
    *) printf 'Unknown native OSD: %s\n' "$kind" >&2; return 2 ;;
  esac
  local mute_override=""
  if [[ "$kind" == mic-volume && $# -eq 1 && ( "$1" == muted || "$1" == unmuted ) ]]
  then
    mute_override=1
  fi
  if (( $# > 1 )) || { (( $# == 1 )) && [[ -z "$mute_override" ]] && ! jq -en --arg v "$1" '$v | tonumber | . >= 0 and . <= 100' >/dev/null 2>&1; }
  then
    printf 'Expected a percentage from 0 to 100\n' >&2
    return 2
  fi
  if ! use_noctalia
  then
    printf 'Native OSDs require a running Noctalia instance\n' >&2
    return 1
  fi
  if [[ -n "$mute_override" ]]
  then
    noctalia msg "${kind}-osd" "$1"
  elif (( $# == 1 ))
  then
    noctalia msg "${kind}-osd" "${1}%"
  else
    noctalia msg "${kind}-osd"
  fi
}

main() {
  if [[ "${1:-}" == native ]]
  then
    shift
    native_osd "$@"
    return $?
  fi
  local icon="" severity=info details="" app_name=osd category="" timeout="" progress="" inactive=""
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help) usage; return 0 ;;
      --inactive) inactive=1; shift ;;
      -i|--icon|-s|--severity|-d|--details|-a|--app-name|-c|--category|-t|--timeout|--progress)
        if [[ -z "${2:-}" ]]
        then
          printf 'Missing value for %s\n' "$1" >&2
          return 2
        fi
        case "$1" in
          -i|--icon) icon="$2" ;;
          -s|--severity) severity="$2" ;;
          -d|--details) details="$2" ;;
          -a|--app-name) app_name="$2" ;;
          -c|--category) category="$2" ;;
          -t|--timeout) timeout="$2" ;;
          --progress) progress="$2" ;;
        esac
        shift 2
        ;;
      --) shift; break ;;
      -*) printf 'Unknown option: %s\n' "$1" >&2; return 2 ;;
      *) break ;;
    esac
  done
  if [[ -z "${1:-}" ]]
  then
    printf 'Missing message\n' >&2
    return 2
  fi
  case "$severity" in
    info) icon="${icon:-info-circle}" ;;
    warn) icon="${icon:-alert-triangle}" ;;
    error) icon="${icon:-alert-circle}" ;;
    *) printf 'Invalid severity: %s\n' "$severity" >&2; return 2 ;;
  esac
  if [[ -n "$progress" ]] && ! jq -en --arg v "$progress" '$v | tonumber | . >= 0 and . <= 1' >/dev/null 2>&1
  then
    printf 'Expected progress from 0 to 1\n' >&2
    return 2
  fi
  local message="$*" payload
  [[ -n "$details" ]] && message+=" — $details"
  if use_noctalia
  then
    payload=$(jq -nc --arg icon "$icon" --arg value "$message" \
      --argjson progress "${progress:-null}" --arg inactive "$inactive" \
      '{icon:$icon, value:$value} + (if $progress == null then {} else {progress:$progress} end) + (if $inactive == "" then {} else {inactive:true} end)')
    noctalia msg osd-show "$payload" &>/dev/null && return 0
  fi
  local -a args=(--app-name "$app_name")
  [[ -n "$timeout" ]] && args+=(-t "$timeout")
  [[ -n "$category" ]] && args+=(--hint "string:x-canonical-private-synchronous:${category}")
  case "$severity" in
    error) args+=(--urgency critical) ;;
    warn) args+=(--urgency normal) ;;
    *) args+=(--urgency low) ;;
  esac
  notify-send "${args[@]}" "$*" "$details"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
