#!/usr/bin/env bash

GO_HASS_AGENT_UNIT="go-hass-agent.service"
MATCH="type='signal',sender='net.hadess.PowerProfiles',path='/net/hadess/PowerProfiles',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"
NOTIFY_APP_NAME="power-profiles-daemon"

log_warn() {
  printf '%s\n' "warning: $*" >&2
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

  local sessions
  if ! sessions="$(loginctl list-sessions --no-legend --no-pager 2>/dev/null)"
  then
    log_warn "loginctl list-sessions failed"
    return 0
  fi

  local line
  while IFS= read -r line
  do
    local session_id
    if ! session_id="$(printf '%s' "$line" | awk '{print $1}')" || \
       [[ -z $session_id ]]
    then
      continue
    fi

    local uid
    if ! uid="$(loginctl show-session "$session_id" -p User --value 2>/dev/null)"
    then
      continue
    fi

    local display
    if ! display="$(loginctl show-session "$session_id" -p Display --value 2>/dev/null)"
    then
      display=""
    fi

    if [[ -z "$uid" ]]
    then
      continue
    fi

    local runtime_dir="/run/user/$uid"
    local bus="$runtime_dir/bus"
    if [[ ! -S "$bus" ]]
    then
      continue
    fi

    if [[ -n "$display" ]]
    then
      if ! DISPLAY="$display" \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        runuser -u "#$uid" -- notify-send -a "$NOTIFY_APP_NAME" "$summary" "$body"
      then
        :
      fi
    else
      if ! XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        runuser -u "#$uid" -- notify-send -a "$NOTIFY_APP_NAME" "$summary" "$body"
      then
        :
      fi
    fi
  done <<<"$sessions"
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
