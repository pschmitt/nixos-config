#!/usr/bin/env bash

# Ask the user for help in a headless browser (CAPTCHA, approval on another
# device, a password they should type themselves, ...): send a Home Assistant
# notification (phone push, Signal, or both) whose link opens the browser-daemon
# live view of the agent's own page, where the user can click and type in the
# very session the agent is driving.
#
# Agents call it through the browser MCP's browser_ask_human tool
# (`browser-daemon mcp --ask-human-cmd`), which passes the page and node in
# BD_PAGE, BD_NODE, BD_TITLE and BD_AGENT; run by hand, name them with options.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] MESSAGE

  --page ID        open this page directly (BD_PAGE; the browser MCP's
                   browser_ask_human passes the agent's own page)
  --match REGEX    pick the page whose URL matches REGEX instead; there must be
                   exactly one match (the browser is shared with other agents)
  --host HOST      browser node (BD_NODE): fnuc (default), rofl-13, ...
  --url WHICH      which link: auto (default; the mesh link when Home Assistant
                   says the user is home, else the public one), mesh or public
  --via WAY        push (default), signal or both (BD_VIA)
  --phone NAME     notify.mobile_app_NAME target (default: pixel_11_pro)
  --title TITLE    push title (default: "Claude needs you in the browser")
  --harness NAME   harness shown in the Signal heading (default: CLAUDE CODE)

Without --page/--match the link opens a list of the browser's pages to pick
from. There are two links to the same phone-friendly live view (source:
handoff.html in the browser-daemon repository):
  mesh    https://browser.HOST.${BROWSER_MESH_DOMAIN:-nb.brkn.lol}/handoff/?page=ID
          tailnet/Netbird only, no login
  public  https://browser.HOST.${BROWSER_PUBLIC_DOMAIN:-brkn.lol}/handoff/?page=ID
          reachable from anywhere, Authelia (owner only, two-factor)
The user is usually not on the mesh when away, hence auto.

Tell the user in MESSAGE what to do ("Solve the CAPTCHA, then tap Next"), keep
the page open and untouched meanwhile, then re-check it before continuing.
EOF
}

mesh_base() {
  printf 'browser.%s.%s' "$1" "${BROWSER_MESH_DOMAIN:-nb.brkn.lol}"
}

public_base() {
  printf 'browser.%s.%s' "$1" "${BROWSER_PUBLIC_DOMAIN:-brkn.lol}"
}

# Prints the id of the one page whose URL matches the regex.
find_page() {
  local base="$1" regex="$2" ids count

  ids="$(curl -fsS --max-time 15 "https://${base}/json/list" |
    jq -r --arg re "$regex" '.[] | select(.type == "page" and (.url | test($re))) | .id')"
  count="$(grep -c . <<<"$ids" || true)"

  if [[ "$count" != 1 ]]
  then
    printf 'Expected exactly one page matching %s, found %s\n' "$regex" "$count" >&2
    return 1
  fi
  printf '%s\n' "$ids"
}

live_url() {
  local base="$1" page="$2"

  if [[ -n "$page" ]]
  then
    printf 'https://%s/handoff/?page=%s' "$base" "$page"
  else
    printf 'https://%s/handoff/' "$base"
  fi
}

HA_URL="${HASS_SERVER:-http://10.5.1.1:8123}"

# Prefer the token of the dedicated "AI Agent" HA user (see /mnt/ha/AGENTS.md).
# This script is often the way out when rbw is locked, so fall back to the
# sops-backed personal token instead of failing.
ha_token() {
  local token

  if rbw unlocked &>/dev/null
  then
    token="$(rbw get --field "Long-Lived Access Token" "Home Assistant (AI Agent)" 2>/dev/null)"
  fi
  if [[ -z "${token:-}" ]]
  then
    read -r _ token < <(zsh -lc 'zhj hass::secrets-gu5a')
  fi
  if [[ -z "${token:-}" ]]
  then
    printf 'Could not read a Home Assistant token (rbw "Home Assistant (AI Agent)" or zhj hass::secrets-gu5a)\n' >&2
    return 1
  fi
  printf '%s\n' "$token"
}

# curl wrapper that passes the bearer token as a header file, off argv.
ha_curl() {
  local token

  token="$(ha_token)" || return 1
  curl -H @<(printf 'Authorization: Bearer %s\n' "$token") "$@"
}

# Is the user at home (and therefore on the mesh)? Home Assistant knows.
user_is_home() {
  local state

  state="$(ha_curl -fsS --max-time 10 \
    "${HA_URL%/}/api/states/person.philipp_schmitt" | jq -r '.state')" || return 1
  [[ "$state" == home ]]
}

ha_call() {
  local service="$1" payload="$2"

  ha_curl -fsS -X POST "${HA_URL%/}/api/services/notify/${service}" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null
}

send_push() {
  local phone="$1" title="$2" message="$3" live="$4"

  ha_call "mobile_app_${phone}" "$(jq -n \
    --arg title "$title" --arg message "$message" --arg live "$live" '{
      title: $title,
      message: $message,
      data: {
        clickAction: $live,
        url: $live,
        tag: "agent-browser-handoff",
        channel: "Agent handoff",
        importance: "high",
        priority: "high",
        ttl: 0,
        timeout: 3600,
        actions: [{action: "URI", title: "Open browser", uri: $live}]
      }
    }')"
}

# Signal updates start with an uppercase [TOPIC | HARNESS] line (see CONTEXT.md).
send_signal() {
  local harness="$1" message="$2" live="$3"

  ha_call signal_me "$(jq -n \
    --arg message "$(printf '**[BROWSER HANDOFF | %s]**\n%s\n%s' "$harness" "$message" "$live")" \
    '{message: $message}')"
}

main() {
  # Defaults from browser-daemon mcp (browser_ask_human), when it runs this.
  local host="${BD_NODE:-fnuc}" phone=pixel_11_pro via="${BD_VIA:-push}"
  local harness="${BD_AGENT:-claude code}" title="${BD_TITLE:-}" message=""
  local page="${BD_PAGE:-}" match="" which=auto
  local base live

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --page)
        page="$2"
        shift 2
        ;;
      --match)
        match="$2"
        shift 2
        ;;
      --host)
        host="$2"
        shift 2
        ;;
      --via)
        via="$2"
        shift 2
        ;;
      --url)
        which="$2"
        shift 2
        ;;
      --phone)
        phone="$2"
        shift 2
        ;;
      --title)
        title="$2"
        shift 2
        ;;
      --harness)
        harness="$2"
        shift 2
        ;;
      *)
        message="$1"
        shift
        ;;
    esac
  done

  title="${title:-Claude needs you in the browser}"
  harness="${harness//-/ }"
  harness="${harness^^}"
  if [[ -z "$message" || ! "$via" =~ ^(push|signal|both)$ || ! "$which" =~ ^(auto|mesh|public)$ ]]
  then
    usage >&2
    return 2
  fi

  base="$(mesh_base "$host")"
  if [[ -z "$page" && -n "$match" ]]
  then
    page="$(find_page "$base" "$match")" || return 1
  fi
  if [[ "$which" == auto ]]
  then
    if user_is_home
    then
      which=mesh
    else
      which=public
    fi
    printf 'User is %s: using the %s link\n' "$([[ "$which" == mesh ]] && echo home || echo away)" "$which"
  fi
  if [[ "$which" == public ]]
  then
    live="$(live_url "$(public_base "$host")" "$page")"
  else
    live="$(live_url "$base" "$page")"
  fi

  if [[ "$via" == push || "$via" == both ]]
  then
    send_push "$phone" "$title" "$message" "$live" || return 1
    printf 'Push sent to %s\n' "$phone"
  fi
  if [[ "$via" == signal || "$via" == both ]]
  then
    send_signal "$harness" "$message" "$live" || return 1
    printf 'Signal message sent\n'
  fi
  printf 'Link: %s\n' "$live"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
