#!/usr/bin/env bash

# Ask the user for help in a headless browser (CAPTCHA, approval on another
# device, a password they should type themselves, ...): send a Home Assistant
# notification (phone push, Signal, or both) whose link opens the Browserless
# live view of the agent's own page, where the user can click and type in the
# very session the agent is driving.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] MESSAGE

  --page ID        open this page directly (the agent's own page id:
                   (await (await page.context().newCDPSession(page))
                     .send('Target.getTargetInfo')).targetInfo.targetId)
  --match REGEX    pick the page whose URL matches REGEX instead; there must be
                   exactly one match (the browser is shared with other agents)
  --host HOST      browser host: fnuc (default), rofl-13, rofl-14
  --url WHICH      which link: auto (default; the mesh link when Home Assistant
                   says the user is home, else the public one), mesh or public
  --via WAY        push (default), signal or both
  --phone NAME     notify.mobile_app_NAME target (default: pixel_11_pro)
  --title TITLE    push title (default: "Claude needs you in the browser")
  --harness NAME   harness shown in the Signal heading (default: CLAUDE CODE)

Without --page/--match the link opens a list of the browser's pages to pick
from. There are two links to the same phone-friendly live view (source:
services/headless-browsers/handoff.html in nixos-config):
  mesh    https://browserless.HOST.${BROWSERLESS_DOMAIN:-ts.brkn.lol}/handoff/?page=ID
          tailnet/Netbird only, no login
  public  https://browser-HOST.${BROWSERLESS_PUBLIC_DOMAIN:-brkn.lol}/handoff/?page=ID
          reachable from anywhere, Authelia (owner only, two-factor)
The user is usually not on the mesh when away, hence auto.

Tell the user in MESSAGE what to do ("Solve the CAPTCHA, then tap Next"), keep
the page open and untouched meanwhile, then re-check it before continuing.
EOF
}

browserless_base() {
  printf 'browserless.%s.%s' "$1" "${BROWSERLESS_DOMAIN:-ts.brkn.lol}"
}

public_base() {
  printf 'browser-%s.%s' "$1" "${BROWSERLESS_PUBLIC_DOMAIN:-brkn.lol}"
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

ha_credentials() {
  local url token

  read -r url token < <(zsh -lc 'zhj hass::secrets-gu5a')
  if [[ -z "$url" || -z "$token" ]]
  then
    printf 'Could not read the Home Assistant credentials (zhj hass::secrets-gu5a)\n' >&2
    return 1
  fi
  printf '%s %s\n' "${url%/}" "$token"
}

# Is the user at home (and therefore on the mesh)? Home Assistant knows.
user_is_home() {
  local url token state

  read -r url token < <(ha_credentials) || return 1
  state="$(curl -fsS --max-time 10 -H "Authorization: Bearer ${token}" \
    "${url}/api/states/person.philipp_schmitt" | jq -r '.state')" || return 1
  [[ "$state" == home ]]
}

ha_call() {
  local service="$1" payload="$2" url token

  read -r url token < <(ha_credentials) || return 1
  curl -fsS -X POST "${url}/api/services/notify/${service}" \
    -H "Authorization: Bearer ${token}" \
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
  local host=fnuc phone=pixel_11_pro via=push harness="CLAUDE CODE"
  local title="Claude needs you in the browser" message="" page="" match="" which=auto
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

  if [[ -z "$message" || ! "$via" =~ ^(push|signal|both)$ || ! "$which" =~ ^(auto|mesh|public)$ ]]
  then
    usage >&2
    return 2
  fi

  base="$(browserless_base "$host")"
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
