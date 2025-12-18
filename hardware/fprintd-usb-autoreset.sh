#!/usr/bin/env bash

set -euo pipefail

FPRINTD_UNIT="fprintd.service"
NOTIFY_APP_NAME="fprintd-usb-autoreset"
DEVICE_NAME="${DEVICE_NAME:-}"

log_warn() {
  printf '%s\n' "warning: $*" >&2
}

should_notify() {
  [[ -n "${NOTIFY:-}" ]]
}

notify_all_sessions() {
  local summary="$1"
  local body="$2"

  if ! should_notify
  then
    return 0
  fi

  local sessions_json
  if ! sessions_json="$(loginctl list-sessions --no-pager -j 2>/dev/null)"
  then
    log_warn "loginctl list-sessions failed"
    return 0
  fi

  local uid user
  while IFS=$'\t' read -r uid user
  do
    if [[ -z "$uid" || -z "$user" ]]
    then
      continue
    fi

    local runtime_dir="/run/user/$uid"
    local bus="$runtime_dir/bus"
    if [[ ! -S "$bus" ]]
    then
      continue
    fi

    if ! XDG_RUNTIME_DIR="$runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      runuser -u "$user" -- notify-send -a "$NOTIFY_APP_NAME" "$summary" "$body"
    then
      log_warn "notify-send failed for user $user (uid $uid)"
    fi
  done < <(
    jq -r '
      [
        .[]
        | select(.class == "user")
        | { uid, user }
      ]
      | unique_by(.uid)
      | .[]
      | "\(.uid)\t\(.user)"
    ' <<<"$sessions_json"
  )
}

fprintd_device_count() {
  local json

  if ! json="$(
    busctl --system --json=short call \
      net.reactivated.Fprint \
      /net/reactivated/Fprint/Manager \
      net.reactivated.Fprint.Manager \
      GetDevices 2>/dev/null
  )"
  then
    return 1
  fi

  jq -er '
    def unwrap:
      if type == "object" and has("type") and has("data")
      then
        .data | unwrap
      elif type == "array"
      then
        map(unwrap)
      else
        .
      end;

    [
      unwrap
      | .. | strings
      | select(startswith("/"))
    ]
    | length
  ' <<<"$json" 2>/dev/null
}

find_fingerprint_usb_id() {
  if [[ -z "$DEVICE_NAME" ]]
  then
    log_warn "DEVICE_NAME is empty"
    return 1
  fi

  lsusb \
    | jc --lsusb \
    | jq -er --arg deviceName "$DEVICE_NAME" '
      [
        .[]
        | select((.description // "") as $d | ($d == $deviceName or ($d | contains($deviceName))))
      ][0]
      | .id
    '
}

main() {
  local count
  if count="$(fprintd_device_count)"
  then
    if [[ "$count" -gt 0 ]]
    then
      printf '%s\n' "ok: fprintd reports $count device(s); nothing to do"
      exit 0
    fi
  else
    log_warn "failed to query fprintd devices (assuming none)"
  fi

  local device_id
  if ! device_id="$(find_fingerprint_usb_id 2>/dev/null)"
  then
    log_warn "no fingerprint USB device found via lsusb"

    if ! systemctl restart "$FPRINTD_UNIT"
    then
      log_warn "failed to restart $FPRINTD_UNIT"
    fi

    notify_all_sessions "Fingerprint reader unavailable" "Restarted fprintd (USB device not found)"
    exit 0
  fi

  if ! usbreset "$device_id"
  then
    log_warn "usbreset failed for $device_id"
    exit 0
  fi

  if ! systemctl restart "$FPRINTD_UNIT"
  then
    log_warn "failed to restart $FPRINTD_UNIT after usbreset"
  fi

  notify_all_sessions "Fingerprint reader reset" "USB reset $device_id and restarted fprintd"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
