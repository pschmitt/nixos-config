# wofi-menu — Nix-native port of the zhj-backed ~/bin/wofi.zsh launcher:
# the run, emoji, soundboard, misc and meetings menus. The bitwarden menus
# were dropped (unused). With this, nothing references ~/bin/wofi.zsh anymore.

DATA_DIR="${XDG_DOCUMENTS_DIR:-$HOME/Documents}/data"
BANKING_DIR="${HOME}/Documents/Banking"
MSTEAMS_FILE="${DATA_DIR}/ms-teams-meetings.json"
PHONE_FILE="${DATA_DIR}/phone-numbers.json"
JCAL_HOST="${JCAL_HOST:-http://localhost:7042}"
BROWSER_LAUNCHER="${HOME}/.config/hypr/bin/browser-run-or-raise.sh"

usage() {
  echo "Usage: wofi-menu {run|emoji|soundboard [stop]|misc|meetings}" >&2
}

# Close any open wofi first (so a second keypress toggles it shut).
kill_wofi() {
  { killall wofi; killall .wofi-wrapped; } >/dev/null 2>&1 || true
}

clip() {
  local value="$1" message="$2" icon="${3:-}"
  printf '%s' "$value" | wl-copy
  if [[ -n "$icon" ]]
  then
    notify-send -a wofi-menu -i "$icon" "$message"
  else
    notify-send -a wofi-menu "$message"
  fi
}

run_menu() {
  local cmd
  cmd="$(wofi --insensitive --show=drun --prompt="󰜎 Run" --define=drun-print_command=true)"

  if [[ -z "$cmd" ]]
  then
    echo "No command selected" >&2
    exit 1
  fi

  # DIRTYFIX (from the original): force the GTK theme for launched apps.
  local theme
  theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'\"")"

  notify-send -a "wofi-run" "󰜎 Launching \"$cmd\""

  # Launch detached so the app survives this process exiting. Inherits the
  # session env (WAYLAND_DISPLAY etc) from the keybind that invoked us.
  if [[ -n "$theme" ]]
  then
    setsid -f sh -c "GTK_THEME=$theme $cmd"
  else
    setsid -f sh -c "$cmd"
  fi
}

emoji_menu() {
  local emoji
  emoji="$(emoji-fzf --custom-aliases "$HOME/.config/emoji-fzf/emojis.json" preview --prepend \
    | sed -r 's/&/&amp;/g; s/_/ /g; s/^(\S+)\s+(.+)$/\1 <span foreground="gray">\2<\/span>/' \
    | wofi --show dmenu \
        --insensitive \
        --matching fuzzy \
        --allow-markup \
        --prompt "🎩 Emoji selection lol" \
    | awk '{print $1}' | tr -d '\n')"

  if [[ -z "$emoji" ]]
  then
    echo "No emoji selected" >&2
    return 1
  fi

  printf '%s' "$emoji" | wl-copy
  notify-send -a "wofi-emoji" "📋 Copied $emoji to clipboard"
}

soundboard_menu() {
  local -a sounds
  mapfile -t sounds < <(soundboard list)

  local res
  res="$(printf '%s\n' "${sounds[@]}" \
    | wofi --dmenu -p "🎹 What are we playing?" -l "${#sounds[@]}" -i)"

  [[ -z "$res" ]] && return 1

  soundboard play "$res"
}

# IBANs (~/Documents/Banking/*/accounts.json) + phone numbers. The bitwarden
# password entries from the original are intentionally dropped.
misc_menu() {
  local -A items=()
  local label value

  if compgen -G "$BANKING_DIR/*/accounts.json" >/dev/null 2>&1
  then
    while IFS=$'\t' read -r label value
    do
      [[ -n "$label" ]] && items["$label"]="iban:$value"
    done < <(cat "$BANKING_DIR"/*/accounts.json 2>/dev/null | jq -rs '
      .[] | . as $bank | .accounts[]?
      | select(.iban != null and .iban != "")
      | ["\($bank.emoji) \($bank.bank) (\(.name))", .iban] | @tsv')
  fi

  if [[ -f "$PHONE_FILE" ]]
  then
    while IFS=$'\t' read -r label value
    do
      [[ -n "$label" ]] && items["$label"]="phone:$value"
    done < <(jq -r '
      .[]
      | (.display_name + " " + .msisdn + "\t" + .msisdn),
        (if (.national // "") != "" and .national != .msisdn
         then .display_name + " " + .national + "\t" + .national
         else empty end)' "$PHONE_FILE")
  fi

  if [[ "${#items[@]}" -eq 0 ]]
  then
    notify-send -a wofi-menu "📋 No misc entries found"
    return 1
  fi

  local res
  res="$(printf '%s\n' "${!items[@]}" | sort | wofi --dmenu -p "📋 What do you want?" -i)"
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

  if [[ -f "$MSTEAMS_FILE" ]]
  then
    while IFS=$'\t' read -r label url
    do
      [[ -n "$label" && -n "$url" ]] && items["$label"]="$url"
    done < <(jq -r '.[] | [.display_name, .url] | @tsv' "$MSTEAMS_FILE")
  fi

  # Calendar agenda: today, or tomorrow after 20:00 / when today is empty.
  local endpoint="today" agenda tmrw=""
  [[ "$(date +%H)" -gt 20 ]] && endpoint="tomorrow"
  agenda="$(curl -s "${JCAL_HOST}/${endpoint}" 2>/dev/null || true)"
  if [[ "$endpoint" == "today" && "$(jq 'length' <<< "$agenda" 2>/dev/null || echo 0)" == "0" ]]
  then
    endpoint="tomorrow"
    agenda="$(curl -s "${JCAL_HOST}/tomorrow" 2>/dev/null || true)"
  fi
  [[ "$endpoint" == "tomorrow" ]] && tmrw=" [TMRW]"

  local ev start end stime etime summary loc title
  while IFS= read -r ev
  do
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
    if [[ "$stime" != "00:00" || "$etime" != "00:00" ]]
    then
      title+=" ${stime}-${etime}"
    fi
    title+=" ${summary}"
    items["$title"]="$loc"
  done < <(jq -c '.[]?' <<< "$agenda" 2>/dev/null)

  if [[ "${#items[@]}" -eq 0 ]]
  then
    notify-send -a wofi-menu "🌐 No meetings found"
    return 1
  fi

  local res
  res="$(printf '%s\n' "${!items[@]}" | sort | wofi --dmenu -p "🌐 Select meeting to join" -i)"
  [[ -z "$res" ]] && exit 1

  url="${items[$res]}"
  if [[ -z "$url" || "$url" == "null" ]]
  then
    notify-send -a wofi-menu "❌ No conference URL for $res"
    return 1
  fi

  notify-send -a wofi-menu "🌐 Joining $res"

  if [[ -x "$BROWSER_LAUNCHER" ]]
  then
    "$BROWSER_LAUNCHER" \
      --browser chromium \
      --new-window \
      --title "$res | Microsoft Teams" \
      --url "$url"
  else
    setsid -f xdg-open "$url"
  fi
}

kill_wofi

case "${1:-}" in
  run)
    shift
    run_menu
    ;;
  emoji | emoj* | e)
    emoji_menu
    ;;
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
