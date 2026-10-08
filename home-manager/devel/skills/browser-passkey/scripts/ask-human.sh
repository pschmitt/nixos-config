#!/usr/bin/env bash

# Ask the user for help in a headless browser (CAPTCHA, approval on another
# device, ...): send an actionable Home Assistant push notification whose tap
# opens the Browserless live view of that host's browser, where the user can
# click and type in the very session the agent is driving.

usage() {
  cat <<EOF
Usage: $(basename "$0") [--host HOST] [--phone NAME] [--title TITLE] MESSAGE

  --host HOST     browser host whose live view to open: fnuc (default),
                  rofl-13, rofl-14
  --phone NAME    notify.mobile_app_NAME target (default: pixel_11_pro, the
                  user's main phone)
  --title TITLE   notification title (default: "Claude needs you in the browser")

The live view is https://browserless.HOST.\${BROWSERLESS_DOMAIN:-ts.brkn.lol}/debugger/
(reachable from the tailnet without a login; Authelia protects it elsewhere).
Tell the user *what* to do in MESSAGE, e.g. "Solve the Google CAPTCHA, then tap
Next", and keep the session open and idle while they work, then re-check the
page (snapshot) before continuing.
EOF
}

main() {
  local host=fnuc phone=pixel_11_pro title="Claude needs you in the browser" message=""
  local url token live payload

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --host)
        host="$2"
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
      *)
        message="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$message" ]]
  then
    usage >&2
    return 2
  fi

  read -r url token < <(zsh -lc 'zhj hass::secrets-gu5a')
  if [[ -z "$url" || -z "$token" ]]
  then
    printf 'Could not read the Home Assistant credentials (zhj hass::secrets-gu5a)\n' >&2
    return 1
  fi

  live="https://browserless.${host}.${BROWSERLESS_DOMAIN:-ts.brkn.lol}/debugger/"
  payload="$(jq -n --arg title "$title" --arg message "$message" --arg live "$live" '{
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

  curl -fsS -X POST "${url%/}/api/services/notify/mobile_app_${phone}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null || return 1
  printf 'Notification sent to %s, opens %s\n' "$phone" "$live"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
