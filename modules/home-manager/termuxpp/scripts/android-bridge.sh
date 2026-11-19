#!/usr/bin/env bash
# android-bridge: the former native broker's commands, now plain Termux:API
# calls through the app's am socket (the one guest-to-Android channel).

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") ping|status|battery-status|toast TEXT...

Allowlisted Android actions from the guest through the TermuxPP app's
Termux:API (the app's am socket; no separate broker):
  ping            check that the app answers (no side effects)
  status          show the channel and the API helpers in use
  battery-status  print battery status as JSON
  toast TEXT      show an Android toast
EOF_USAGE
}

main() {
  case ${1:-} in
    ping)
      local output=''
      if ! output=$(timeout 20 termux-battery-status 2>&1) || ! jq -e . >/dev/null 2>&1 <<<"$output"
      then
        printf 'android-bridge: the TermuxPP app does not answer: %s\n' "${output:-no output}" >&2
        return 1
      fi
      printf '{"ok":true,"channel":"termux-api"}\n'
      ;;
    status)
      jq -cn --arg api "$(command -v termux-battery-status)" \
        '{channel: "termux-api", transport: "app am socket", api: $api}'
      ;;
    battery-status)
      exec termux-battery-status
      ;;
    toast)
      shift
      if (($# == 0))
      then
        usage >&2
        return 2
      fi
      exec termux-toast "$@"
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
