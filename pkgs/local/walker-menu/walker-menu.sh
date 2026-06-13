# walker-menu — soundboard/misc/meetings menus backed by walker dmenu.
# The run and emoji modes are now called directly via walker / walker -m emojis.

DATA_DIR="${XDG_DOCUMENTS_DIR:-$HOME/Documents}/data"
BANKING_DIR="${HOME}/Documents/Banking"
MSTEAMS_FILE="${DATA_DIR}/ms-teams-meetings.json"
PHONE_FILE="${DATA_DIR}/phone-numbers.json"
JCAL_HOST="${JCAL_HOST:-http://localhost:7042}"
BROWSER_LAUNCHER="${HOME}/.config/hypr/bin/browser-run-or-raise.sh"

usage() {
  echo "Usage: walker-menu {soundboard [stop]|misc|meetings}" >&2
}

kill_walker() {
  walker --close 2>/dev/null || true
}

clip() {
  local value="$1" message="$2" icon="${3:-}"
  printf '%s' "$value" | wl-copy
  if [[ -n "$icon" ]]; then
    notify-send -a walker-menu -i "$icon" "$message"
  else
    notify-send -a walker-menu "$message"
  fi
}

soundboard_menu() {
  local -a sounds
  mapfile -t sounds < <(soundboard list)

  local res
  res="$(printf '%s\n' "${sounds[@]}" \
    | walker --dmenu -p "🎹 What are we playing?")"

  [[ -z "$res" ]] && return 1

  soundboard play "$res"
}

# IBANs (~/Documents/Banking/*/accounts.json) + phone numbers.
misc_menu() {
  local -A items=()
  local label value

  if compgen -G "$BANKING_DIR/*/accounts.json" >/dev/null 2>&1; then
    while IFS=$'\t' read -r label value; do
      [[ -n "$label" ]] && items["$label"]="iban:$value"
    done < <(cat "$BANKING_DIR"/*/accounts.json 2>/dev/null | jq -rs '
      .[] | . as $bank | .accounts[]?
      | select(.iban != null and .iban != "")
      | ["\($bank.emoji) \($bank.bank) (\(.name))", .iban] | @tsv')
  fi

  if [[ -f "$PHONE_FILE" ]]; then
    while IFS=$'\t' read -r label value; do
      [[ -n "$label" ]] && items["$label"]="phone:$value"
    done < <(jq -r '
      .[]
      | (.display_name + " " + .msisdn + "\t" + .msisdn),
        (if (.national // "") != "" and .national != .msisdn
         then .display_name + " " + .national + "\t" + .national
         else empty end)' "$PHONE_FILE")
  fi

  if [[ "${#items[@]}" -eq 0 ]]; then
    notify-send -a walker-menu "📋 No misc entries found"
    return 1
  fi

  local res
  res="$(printf '%s\n' "${!items[@]}" | sort | walker --dmenu -p "📋 What do you want?")"
  [[ -z "$res" ]] && exit 1

  local entry="${items[$res]}"
  local kind="${entry%%:*}" val="${entry#*:}"

  case "$kind" in
    iban) clip "$val" "$res ($val)" ;;
    phone) clip "$val" "$res" ;;
    *) echo "nope..." >&2 ;;
  esac
}

# Static MS Teams meetings + dynamic calendar agenda (jcal == GET on the
# local calendar service). Join via the existing browser-run-or-raise helper.
meetings_menu() {
  local -A items=()
  local label url

  if [[ -f "$MSTEAMS_FILE" ]]; then
    while IFS=$'\t' read -r label url; do
      [[ -n "$label" && -n "$url" ]] && items["$label"]="$url"
    done < <(jq -r '.[] | [.display_name, .url] | @tsv' "$MSTEAMS_FILE")
  fi

  local endpoint="today" agenda tmrw=""
  [[ "$(date +%H)" -gt 20 ]] && endpoint="tomorrow"
  agenda="$(curl -s "${JCAL_HOST}/${endpoint}" 2>/dev/null || true)"
  if [[ "$endpoint" == "today" && "$(jq 'length' <<< "$agenda" 2>/dev/null || echo 0)" == "0" ]]; then
    endpoint="tomorrow"
    agenda="$(curl -s "${JCAL_HOST}/tomorrow" 2>/dev/null || true)"
  fi
  [[ "$endpoint" == "tomorrow" ]] && tmrw=" [TMRW]"

  local ev start end stime etime summary loc title
  while IFS= read -r ev; do
    [[ -z "$ev" ]] && continue
    loc="$(jq -r '
      def known: [.. | strings
        | select(test("https://(meet\\.google\\.com|teams\\.microsoft\\.com|.*zoom\\.us)/"))][0];
      .conference_url // .location // .extra.meeting_workspace_url
      // .extra.net_show_url // .extra.link // known // empty' <<< "$ev")"
    [[ -z "$loc" ]] && continue

    start="$(jq -r '.start' <<< "$ev")"
    end="$(jq -r '.end' <<< "$ev")"
    stime="$(date -d "$start" +%H:%M 2>/dev/null || echo '')"
    etime="$(date -d "$end" +%H:%M 2>/dev/null || echo '')"
    summary="$(jq -r '.summary // "N/A"' <<< "$ev")"
    [[ "${#summary}" -gt 55 ]] && summary="${summary:0:55}[…]"

    title="📆${tmrw}"
    if [[ "$stime" != "00:00" || "$etime" != "00:00" ]]; then
      title+=" ${stime}-${etime}"
    fi
    title+=" ${summary}"
    items["$title"]="$loc"
  done < <(jq -c '.[]?' <<< "$agenda" 2>/dev/null)

  if [[ "${#items[@]}" -eq 0 ]]; then
    notify-send -a walker-menu "🌐 No meetings found"
    return 1
  fi

  local res
  res="$(printf '%s\n' "${!items[@]}" | sort | walker --dmenu -p "🌐 Select meeting to join")"
  [[ -z "$res" ]] && exit 1

  url="${items[$res]}"
  if [[ -z "$url" || "$url" == "null" ]]; then
    notify-send -a walker-menu "❌ No conference URL for $res"
    return 1
  fi

  notify-send -a walker-menu "🌐 Joining $res"

  if [[ -x "$BROWSER_LAUNCHER" ]]; then
    "$BROWSER_LAUNCHER" \
      --browser chromium \
      --new-window \
      --title "$res | Microsoft Teams" \
      --url "$url"
  else
    setsid -f xdg-open "$url"
  fi
}

kill_walker

case "${1:-}" in
  soundboard | sb)
    case "${2:-}" in
      stop | halt | end | pause)
        notify-send -t 1000 "🎹 Stopping soundboard playback..."
        soundboard stop
        ;;
      *)
        soundboard_menu
        ;;
    esac
    ;;
  misc | passw* | pwd | p | gpg | common | phone | handy | ph | tel)
    misc_menu
    ;;
  meetings | meet* | zoom | z | m)
    meetings_menu
    ;;
  -h | --help | help | "")
    usage
    [[ "${1:-}" == "" ]] && exit 2 || exit 0
    ;;
  *)
    echo "Unknown action: \"$1\"" >&2
    usage
    exit 2
    ;;
esac
