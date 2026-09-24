#!/usr/bin/env bash

MATCH="type='signal',sender='net.hadess.PowerProfiles',path='/net/hadess/PowerProfiles',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"
NOTIFY_APP_NAME="power-profiles-daemon"
CONFIG_FILE="${PPD_REACT_CONFIG:-/etc/ppd-react.conf}"
STATE_FILE="${PPD_REACT_STATE_FILE:-/run/ppd-react/active-units}"
SYSTEM_UNITS_STOP_ON_POWER_SAVER=()
SYSTEM_UNITS_RESUME_ON_POWER_SAVER_EXIT=()
USER_UNITS_STOP_ON_POWER_SAVER=()
USER_UNITS_RESUME_ON_POWER_SAVER_EXIT=()
ONLY_STOP_UNITS_ON_BATTERY=1

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

has_external_power() {
  local supply online type

  for supply in "${PPD_REACT_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"/*
  do
    [[ -r "$supply/online" ]] || continue
    IFS= read -r online <"$supply/online"
    [[ "$online" == 1 ]] || continue

    if [[ -r "$supply/type" ]]
    then
      IFS= read -r type <"$supply/type"
      [[ "$type" == Battery ]] && continue
    fi

    return 0
  done

  return 1
}

has_battery() {
  local supply type

  for supply in "${PPD_REACT_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"/*
  do
    [[ -r "$supply/type" ]] || continue
    IFS= read -r type <"$supply/type"
    [[ "$type" == Battery ]] && return 0
  done

  return 1
}

external_power_state() {
  if has_external_power
  then
    printf '%s\n' connected
  elif has_battery
  then
    printf '%s\n' battery
  else
    printf '%s\n' unknown
  fi
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

manage_system_units() {
  local action="$1"
  shift

  local unit
  for unit in "$@"
  do
    if ! systemctl --no-block "$action" "$unit"
    then
      log_warn "failed to $action system unit $unit"
    fi
  done
}

manage_user_units() {
  local action="$1"
  shift

  if (($# == 0))
  then
    return 0
  fi

  local sessions_json
  if ! sessions_json="$(loginctl list-sessions --no-pager -j 2>/dev/null)"
  then
    log_warn "loginctl list-sessions failed while managing user units"
    return 0
  fi

  local uid user unit
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

    for unit in "$@"
    do
      if ! user_systemctl "$action" "$uid" "$user" "$unit"
      then
        log_warn "failed to $action user unit $unit for $user (uid $uid)"
      fi
    done
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

is_listed() {
  local wanted="$1"
  shift

  local item
  for item in "$@"
  do
    if [[ "$item" == "$wanted" ]]
    then
      return 0
    fi
  done

  return 1
}

user_systemctl() {
  local action="$1"
  local uid="$2"
  local user="$3"
  local unit="$4"
  local runtime_dir="/run/user/$uid"
  local bus="$runtime_dir/bus"
  local -a systemctl_args=(--user)

  if [[ ! -S "$bus" ]]
  then
    return 1
  fi

  if [[ "$action" == "start" || "$action" == "stop" ]]
  then
    systemctl_args+=(--no-block)
  fi

  runuser -u "$user" -- env \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
    systemctl "${systemctl_args[@]}" "$action" "$unit"
}

capture_resume_state() {
  if [[ -e "$STATE_FILE" ]]
  then
    return 0
  fi

  mkdir -p "${STATE_FILE%/*}"
  : >"$STATE_FILE"
  chmod 0600 "$STATE_FILE"

  local unit uid user sessions_json
  for unit in "${SYSTEM_UNITS_STOP_ON_POWER_SAVER[@]}"
  do
    if is_listed "$unit" "${SYSTEM_UNITS_RESUME_ON_POWER_SAVER_EXIT[@]}" &&
      systemctl is-active --quiet "$unit"
    then
      printf 'system|||%s\n' "$unit" >>"$STATE_FILE"
    fi
  done

  if ! sessions_json="$(loginctl list-sessions --no-pager -j 2>/dev/null)"
  then
    log_warn "loginctl list-sessions failed while capturing active user units"
    return 0
  fi

  while IFS=$'\t' read -r uid user
  do
    if [[ -z "$uid" || -z "$user" ]]
    then
      continue
    fi

    for unit in "${USER_UNITS_STOP_ON_POWER_SAVER[@]}"
    do
      if is_listed "$unit" "${USER_UNITS_RESUME_ON_POWER_SAVER_EXIT[@]}" &&
        user_systemctl is-active "$uid" "$user" "$unit"
      then
        printf 'user|%s|%s|%s\n' "$uid" "$user" "$unit" >>"$STATE_FILE"
      fi
    done
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

restore_captured_units() {
  if [[ ! -f "$STATE_FILE" ]]
  then
    return 0
  fi

  local scope uid user unit
  while IFS='|' read -r scope uid user unit
  do
    case "$scope" in
      system)
        if is_listed "$unit" "${SYSTEM_UNITS_RESUME_ON_POWER_SAVER_EXIT[@]}"
        then
          manage_system_units start "$unit"
        fi
      ;;
      user)
        if is_listed "$unit" "${USER_UNITS_RESUME_ON_POWER_SAVER_EXIT[@]}" &&
          ! user_systemctl start "$uid" "$user" "$unit"
        then
          log_warn "failed to resume user unit $unit for $user (uid $uid)"
        fi
      ;;
    esac
  done <"$STATE_FILE"

  rm -f "$STATE_FILE"
}

start_resume_units() {
  manage_system_units start "${SYSTEM_UNITS_RESUME_ON_POWER_SAVER_EXIT[@]}"
  manage_user_units start "${USER_UNITS_RESUME_ON_POWER_SAVER_EXIT[@]}"
}

apply_power_saver_units() {
  local power_state="$1"

  if [[ -n "$ONLY_STOP_UNITS_ON_BATTERY" && "$power_state" != battery ]]
  then
    restore_captured_units
    start_resume_units
    if [[ "$power_state" == connected ]]
    then
      notify_all_sessions "External power connected" "Started or resumed configured background services"
    else
      notify_all_sessions "Power source unavailable" "Keeping configured background services running"
    fi
    return 0
  fi

  capture_resume_state
  manage_system_units stop "${SYSTEM_UNITS_STOP_ON_POWER_SAVER[@]}"
  manage_user_units stop "${USER_UNITS_STOP_ON_POWER_SAVER[@]}"
  notify_all_sessions "Power profile: power-saver" "Stopped configured background services while on battery"
}

apply_profile() {
  local profile="$1"
  local power_state="$2"

  apply_tdp_profile "$profile"

  case "$profile" in
    power-saver)
      apply_power_saver_units "$power_state"
    ;;
    balanced|performance)
      restore_captured_units
      notify_all_sessions "Power profile: $profile" "Resumed previously active background services"
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
  local last_profile last_power_state
  if ! last_profile="$(get_active_profile)"
  then
    last_profile=""
  fi
  last_power_state="$(external_power_state)"

  if [[ -n "$last_profile" ]]
  then
    apply_profile "$last_profile" "$last_power_state"
  fi

  local msg profile current_power_state wait_status
  while true
  do
    wait_status=0
    if msg="$(
      timeout 5s busctl --system --json=short --match="$MATCH" wait \
        /net/hadess/PowerProfiles \
        org.freedesktop.DBus.Properties \
        PropertiesChanged
    )"
    then
      :
    else
      wait_status="$?"
    fi

    if [[ "$wait_status" -ne 0 && "$wait_status" -ne 124 ]]
    then
      log_warn "busctl wait failed"
      sleep 1
    fi

    profile="$(profile_from_msg "$msg")"
    if [[ -z "$profile" ]]
    then
      if ! profile="$(get_active_profile)"
      then
        profile=""
      fi
    fi

    current_power_state="$(external_power_state)"
    if [[ -n "$profile" && "$profile" != "$last_profile" ]]
    then
      last_profile="$profile"
      apply_profile "$profile" "$current_power_state"
    elif [[ "$current_power_state" != "$last_power_state" && "$last_profile" == power-saver ]]
    then
      apply_power_saver_units "$current_power_state"
    fi

    last_power_state="$current_power_state"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
