#!/usr/bin/env bash

GO_HASS_AGENT_UNIT="go-hass-agent.service"
MATCH="type='signal',sender='net.hadess.PowerProfiles',path='/net/hadess/PowerProfiles',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"
NOTIFY_APP_NAME="power-profiles-daemon"
CONFIG_FILE="${PPD_REACT_CONFIG:-/etc/ppd-react.conf}"

while (($# > 0))
do
  case "$1" in
    --config)
      if (($# < 2))
      then
        printf '%s\n' "error: --config requires a path" >&2
        exit 2
      fi
      CONFIG_FILE="$2"
      shift 2
    ;;
    --config=*)
      CONFIG_FILE="${1#*=}"
      shift
    ;;
    --help|-h)
      printf '%s\n' "usage: ppd-react [--config PATH]"
      exit 0
    ;;
    *)
      printf '%s\n' "error: unknown argument: $1" >&2
      exit 2
    ;;
  esac
done

if [[ -r "$CONFIG_FILE" ]]
then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

log_warn() {
  printf '%s\n' "warning: $*" >&2
}

should_notify() {
  [[ -n "${NOTIFY:-}" ]]
}

apply_tdp_profile() {
  local profile="$1"
  local profile_key
  local limits_variable
  local limits
  local stapm_limit
  local fast_limit
  local slow_limit
  local apu_slow_limit

  if [[ -z "${TDP_COMMAND:-}" ]]
  then
    return 0
  fi

  profile_key="${profile^^}"
  profile_key="${profile_key//-/_}"
  limits_variable="TDP_PROFILE_${profile_key}"
  limits="${!limits_variable:-}"
  if [[ -z "$limits" ]]
  then
    log_warn "no TDP settings configured for power profile $profile"
    return 0
  fi

  read -r stapm_limit fast_limit slow_limit apu_slow_limit <<<"$limits"
  if [[ -z "$stapm_limit" || -z "$fast_limit" || -z "$slow_limit" || -z "$apu_slow_limit" ]]
  then
    log_warn "invalid TDP settings configured for power profile $profile"
    return 0
  fi

  if ! "$TDP_COMMAND" \
    "--stapm-limit=$stapm_limit" \
    "--fast-limit=$fast_limit" \
    "--slow-limit=$slow_limit" \
    "--apu-slow-limit=$apu_slow_limit" >/dev/null
  then
    log_warn "failed to apply TDP settings for power profile $profile"
  fi
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
      | "\(.uid)\t\(.user)"
    ' <<<"$sessions_json"
  )
}

apply_profile() {
  local profile="$1"

  apply_tdp_profile "$profile"

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
