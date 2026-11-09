# teams-messages — list recent Microsoft Teams messages (who, what, channel)
# from the Home Assistant msteams integration.
#
# Reads the `messages` attribute of the "Recent messages" sensor (disabled by
# default in the integration; enable it first) or, with -u, of the "Unread
# chats" sensor. HASS_SERVER and HASS_TOKEN come from the environment; when
# unset they are resolved like the hass::* zsh functions do, with
# `zhj hass::secrets-gu5a`.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

List recent Microsoft Teams messages: time, sender, channel, text.

Options:
  -n, --count N       Show at most N messages (default: 100)
  -1, --last          Only the newest message (same as -n 1)
  -u, --unread        Only the newest unread message of each chat
  -c, --channel TEXT  Only channels/chats whose name contains TEXT
  -f, --from TEXT     Only messages from senders containing TEXT
  -j, --json          Raw JSON instead of a table
  -h, --help          Show this help

Environment (default: whatever hass::secrets-gu5a provides, via zhj):
  HASS_SERVER   Home Assistant base URL
  HASS_TOKEN    Long-lived access token
EOF
}

# shellcheck disable=SC2016 # jq variables, not shell expansions
JQ_SELECT='
  [(.[] | select(.entity_id == $e) | .attributes.messages // [])[]
   | select(($c == "") or (.channel | ascii_downcase | contains($c | ascii_downcase)))
   | select(($f == "") or (.sender | ascii_downcase | contains($f | ascii_downcase)))]
  | .[:($n | tonumber)]'

# shellcheck disable=SC2016
JQ_TABLE='
  reverse[]
  | [(.time | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | localtime | strftime("%m-%d %H:%M")),
     .sender, .channel, (.text | gsub("\\s*\\n\\s*"; " ⏎ "))]
  | @tsv'

# Echo the value of an option that needs one, or fail with usage.
need_value() {
  if [[ -z "${2:-}" ]]
  then
    printf 'Missing value for %s\n' "$1" >&2
    usage >&2
    return 2
  fi
}

main() {
  local count=100 suffix=recent_messages channel="" from="" as_json=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -n|--count)
        need_value "$@" || return 2
        count="$2"
        shift 2
        ;;
      -1|--last)
        count=1
        shift
        ;;
      -u|--unread)
        suffix=unread_chats
        shift
        ;;
      -c|--channel)
        need_value "$@" || return 2
        channel="$2"
        shift 2
        ;;
      -f|--from)
        need_value "$@" || return 2
        from="$2"
        shift 2
        ;;
      -j|--json)
        as_json=1
        shift
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  local server="${HASS_SERVER:-${HASS_URL:-}}" token="${HASS_TOKEN:-}"
  if [[ -z "$server" || -z "$token" ]]
  then
    # Same credentials as the hass::* zsh functions; prints "SERVER TOKEN".
    if ! command -v zhj > /dev/null
    then
      printf 'HASS_SERVER and HASS_TOKEN must be set (zhj not found)\n' >&2
      return 2
    fi
    read -r server token < <(zhj hass::secrets-gu5a) || true
    if [[ -z "$server" || -z "$token" ]]
    then
      printf 'Could not get Home Assistant credentials from hass::secrets-gu5a\n' >&2
      return 1
    fi
  fi

  local states entity_id
  states="$(curl -fsS -H "Authorization: Bearer ${token}" "${server%/}/api/states")" || return 1

  entity_id="$(jq -r --arg s "_${suffix}" \
    '[.[] | select(.entity_id | test("^sensor\\.microsoft_teams.*" + $s + "$"))][0].entity_id // empty' \
    <<< "$states")"
  if [[ -z "$entity_id" ]]
  then
    printf 'No sensor matching *_%s found.\n' "$suffix" >&2
    if [[ "$suffix" == recent_messages ]]
    then
      printf "Enable the 'Recent messages' sensor of the Microsoft Teams integration first.\n" >&2
    fi
    return 1
  fi

  local -a jq_args=(--arg e "$entity_id" --arg c "$channel" --arg f "$from" --arg n "$count")
  if [[ -n "$as_json" ]]
  then
    jq "${jq_args[@]}" "$JQ_SELECT" <<< "$states"
    return
  fi

  {
    printf 'WHEN\tWHO\tCHANNEL\tTEXT\n'
    jq -r "${jq_args[@]}" "${JQ_SELECT} | ${JQ_TABLE}" <<< "$states"
  } | tsvtool
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
