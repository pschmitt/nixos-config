#!/usr/bin/env bash

GO_HASS_AGENT_UNIT="go-hass-agent.service"
MATCH="type='signal',sender='net.hadess.PowerProfiles',path='/net/hadess/PowerProfiles',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"
NOTIFY_APP_NAME="power-profiles-daemon"

log_warn() {
  printf '%s\n' "warning: $*" >&2
}

should_notify() {
  [[ -n "${NOTIFY:-}" ]]
}

get_active_profile() {
  local json

  if ! json="$(
    busctl --system --json=short get-property \
      net.hadess.PowerProfiles \
      /net/hadess/PowerProfiles \
      net.hadess.PowerProfiles \
      ActiveProfile 2>/dev/null
  )"
  then
    return 1
  fi

  local profile
  if ! profile="$(jq -r '.data // empty' <<<"$json" 2>/dev/null)"
  then
    return 1
  fi

  printf '%s\n' "$profile"
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
      | @tsv
    ' <<<"$sessions_json"
  )
}

apply_profile() {
  local profile="$1"

  case "$profile" in
    power-saver)
      if ! systemctl --no-block stop "$GO_HASS_AGENT_UNIT"
      then
        log_warn "failed to stop $GO_HASS_AGENT_UNIT"
      fi
      notify_all_sessions "Power profile: power-saver" "Stopped go-hass-agent"
    ;;
    balanced|performance)
      if ! systemctl --no-block start "$GO_HASS_AGENT_UNIT"
      then
        log_warn "failed to start $GO_HASS_AGENT_UNIT"
      fi
      notify_all_sessions "Power profile: $profile" "Started go-hass-agent"
    ;;
  esac
}

profile_from_msg() {
  local msg="$1"

  if [[ "$msg" != \{* ]]
  then
    case "$msg" in
      *'"ActiveProfile"'*'power-saver'*)
        printf '%s\n' power-saver
      ;;
      *'"ActiveProfile"'*'balanced'*)
        printf '%s\n' balanced
      ;;
      *'"ActiveProfile"'*'performance'*)
        printf '%s\n' performance
      ;;
      *)
        :
      ;;
    esac
    return 0
  fi

  local profile
  if ! profile="$(
    jq -r '
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
        .. | objects | select(has("ActiveProfile")) | .ActiveProfile | unwrap
        | if type == "array" then .[0] else . end
        | select(type == "string")
      ][0] // empty
    ' <<<"$msg" 2>/dev/null
  )"
  then
    return 0
  fi

  case "$profile" in
    power-saver|balanced|performance)
      printf '%s\n' "$profile"
    ;;
    *)
      :
    ;;
  esac
}

main() {
  local last_profile
  last_profile="$(get_active_profile)"

  if [[ -n "$last_profile" ]]
  then
    apply_profile "$last_profile"
  fi

  local msg profile
  while true
  do
    if ! msg="$(
      busctl --system --json=short --match="$MATCH" wait \
        /net/hadess/PowerProfiles \
        org.freedesktop.DBus.Properties \
        PropertiesChanged
    )"
    then
      log_warn "busctl wait failed"
      sleep 1
      continue
    fi

    profile="$(profile_from_msg "$msg")"
    if [[ -z "$profile" ]]
    then
      continue
    fi

    if [[ "$profile" == "$last_profile" ]]
    then
      continue
    fi

    last_profile="$profile"
    apply_profile "$profile"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
