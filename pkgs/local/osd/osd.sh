# osd — fire an ad-hoc on-screen notification.
#
# Tries, in order: Noctalia's pschmitt/osd plugin panels (see
# pkgs/local/noctalia-osd), DMS's native toast IPC (dms ipc call toast ...),
# then notify-send/mako — so scripts and keybinds get a native-looking OSD
# regardless of which bar is active (see toggle-bar.sh). Noctalia has no
# generic "show a custom OSD" primitive of its own (only fixed-purpose ones:
# brightness-osd, volume-osd, ...), hence the dedicated plugin.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] MESSAGE...
       $(basename "$0") dismiss CATEGORY
       $(basename "$0") hide
       $(basename "$0") status

Options:
  -s, --severity {info,warn,error}   Severity (default: info)
  -c, --category CATEGORY            Dedupe/update-in-place key (Noctalia and
                                      DMS only; repeated calls with the same
                                      category replace the previous toast
                                      instead of stacking). Defaults to
                                      --app-name.
  -d, --details TEXT                 Extra detail line (Noctalia and DMS only)
  -x, --command CMD                  Command run when the toast is clicked
                                      (Noctalia and DMS only)
  -i, --icon GLYPH                   Tabler glyph name shown instead of the
                                      severity icon, eg. bluetooth-connected
                                      (Noctalia only)
  -I, --icon-color COLOR             Icon color: a Noctalia palette role
                                      (error, on_surface, ...) or #RRGGBB
                                      (Noctalia only)
  -p, --profile NAME                 Named profile_rules entry to apply
                                      (Noctalia only)
  -S, --style JSON                   Raw style object merged under --icon /
                                      --icon-color, for any other knob the
                                      plugin exposes (Noctalia only). See
                                      pkgs/local/noctalia-osd/README.md
  -a, --app-name NAME                notify-send app name (fallback only,
                                      default: osd)
  -t, --timeout MS                   Auto-dismiss timeout in ms (Noctalia and
                                      notify-send fallback; ignored by DMS)
  -h, --help                         Show this help
EOF
}

use_noctalia() {
  command -v noctalia &>/dev/null && noctalia msg status &>/dev/null
}

# Noctalia panel geometry is static per [[panel]] entry. Keep short messages
# compact, then select a wider bucket from the longest displayed line. The
# estimate assumes roughly 8px per character at the default font size and
# includes the host inset, icon, and icon-to-text gap.
NOCTALIA_PANELS=(
  pschmitt/osd:compact
  pschmitt/osd:toast
  pschmitt/osd:compact-medium
  pschmitt/osd:toast-medium
  pschmitt/osd:compact-wide
  pschmitt/osd:toast-wide
  pschmitt/osd:compact-xwide
  pschmitt/osd:toast-xwide
)

noctalia_panel() {
  local message="$1"
  local details="$2"
  local max_length=${#message}
  if (( ${#details} > max_length ))
  then
    max_length=${#details}
  fi

  local required_width=$((58 + max_length * 8))
  local suffix=""
  if (( required_width > 252 ))
  then
    suffix="-medium"
  fi
  if (( required_width > 320 ))
  then
    suffix="-wide"
  fi
  if (( required_width > 400 ))
  then
    suffix="-xwide"
  fi

  if [[ -n "$details" ]]
  then
    echo "pschmitt/osd:toast${suffix}"
  else
    echo "pschmitt/osd:compact${suffix}"
  fi
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
  local profile="$8"
  local style="${9:-\{\}}"

  if use_noctalia
  then
    # Every per-toast override the plugin understands rides in the payload:
    # "style" is the same key set as its settings, so nothing here needs a
    # config change or a plugin reload. Empty members are dropped so the
    # plugin falls back to its own defaults rather than seeing "".
    local payload
    payload=$(jq -nc \
      --arg summary "$message" \
      --arg body "$details" \
      --arg severity "$severity" \
      --arg category "$category" \
      --arg command "$cmd" \
      --arg profile "$profile" \
      --argjson timeout_ms "${timeout:-null}" \
      --argjson style "$style" \
      '{summary:$summary, body:$body, severity:$severity, category:$category,
        command:$command, timeout_ms:$timeout_ms, profile:$profile, style:$style}
       | with_entries(select(.value != null and .value != "" and .value != {}))')
    noctalia msg panel-open "$(noctalia_panel "$message" "$details")" "$payload" &>/dev/null && return 0
  fi

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

  if use_noctalia
  then
    # Either entry may be the one showing this category.
    local panel rc=1
    for panel in "${NOCTALIA_PANELS[@]}"
    do
      noctalia msg plugin "$panel" all dismiss "$category" &>/dev/null && rc=0
    done
    [[ "$rc" -eq 0 ]] && return 0
  fi

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
  if use_noctalia
  then
    local panel rc=1
    for panel in "${NOCTALIA_PANELS[@]}"
    do
      noctalia msg panel-close "$panel" &>/dev/null && rc=0
    done
    [[ "$rc" -eq 0 ]] && return 0
  fi

  if use_dms
  then
    dms ipc call toast hide &>/dev/null && return 0
  fi

  command -v makoctl &>/dev/null || return 1
  makoctl dismiss --all
}

ipc_status() {
  if use_noctalia
  then
    local active panel
    active=$(noctalia msg status | jq -r '.activePanelId // ""')
    for panel in "${NOCTALIA_PANELS[@]}"
    do
      if [[ "$active" == "$panel" ]]
      then
        echo "active"
        return 0
      fi
    done
    echo "inactive"
    return 0
  fi

  if use_dms
  then
    dms ipc call toast status
    return $?
  fi

  echo "neither noctalia nor dms running; no fallback status available" >&2
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
  local icon="" icon_color="" profile="" style="{}"

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
      -i|--icon)
        icon="$2"
        shift 2
        ;;
      -I|--icon-color)
        icon_color="$2"
        shift 2
        ;;
      -p|--profile)
        profile="$2"
        shift 2
        ;;
      -S|--style)
        style="$2"
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

  if ! jq -e 'type == "object"' <<< "$style" >/dev/null 2>&1
  then
    printf -- '--style must be a JSON object: %s\n' "$style" >&2
    return 2
  fi

  # --icon / --icon-color are just shorthands for two style keys, so they win
  # over the same keys inside --style.
  style=$(jq -c \
    --arg icon "$icon" \
    --arg icon_color "$icon_color" \
    '. + ({icon:$icon, icon_color:$icon_color} | with_entries(select(.value != "")))' \
    <<< "$style")

  send "$severity" "$*" "$details" "$cmd" "$category" "$app_name" "$timeout" \
    "$profile" "$style"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
