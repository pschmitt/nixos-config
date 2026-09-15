# gpd-fan-curve — temperature-dependent control for the GPD Pocket 4 fan.
#
# The gpd_fan driver deliberately leaves temperature feedback to userspace.
# This daemon owns manual PWM mode while it is running and returns the fan to
# the EC curve when it exits.

POLL_SECONDS=5
HYSTERESIS_C=3

# 51 is a known-running quiet floor on this machine (~20%, roughly 1900 RPM).
# Do not lower this without checking that the fan reliably starts again.
MIN_PWM=51

FAN_PWM=""
FAN_ENABLE=""
TEMP_SENSOR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--safe]
  --safe    return the fan to the EC automatic curve and exit
  (default) run the temperature-dependent fan controller
EOF
}

log_message() {
  printf 'gpd-fan-curve: %s\n' "$*"
}

find_hwmon() {
  local wanted="$1"
  local directory
  local name

  for directory in /sys/class/hwmon/hwmon*
  do
    [[ -r "$directory/name" ]] || continue
    name="$(<"$directory/name")"
    if [[ "$name" == "$wanted" ]]
    then
      printf '%s\n' "$directory"
      return 0
    fi
  done

  return 1
}

discover_paths() {
  local fan_hwmon
  local cpu_hwmon

  fan_hwmon="$(find_hwmon gpdfan || true)"
  cpu_hwmon="$(find_hwmon k10temp || true)"

  FAN_PWM=""
  FAN_ENABLE=""
  TEMP_SENSOR=""

  if [[ -n "$fan_hwmon" && -e "$fan_hwmon/pwm1" && -e "$fan_hwmon/pwm1_enable" ]]
  then
    FAN_PWM="$fan_hwmon/pwm1"
    FAN_ENABLE="$fan_hwmon/pwm1_enable"
  fi

  if [[ -n "$cpu_hwmon" && -e "$cpu_hwmon/temp1_input" ]]
  then
    TEMP_SENSOR="$cpu_hwmon/temp1_input"
  fi
}

set_fan_mode() {
  local mode="$1"

  [[ -w "$FAN_ENABLE" ]] || return 1
  printf '%s\n' "$mode" >"$FAN_ENABLE"
}

set_full_speed() {
  if [[ -w "$FAN_ENABLE" ]]
  then
    printf '0\n' >"$FAN_ENABLE" || true
  fi
}

set_auto() {
  if [[ -w "$FAN_ENABLE" ]]
  then
    printf '2\n' >"$FAN_ENABLE" || true
  fi
}

restore_fan() {
  set_auto
}

read_temp_c() {
  local raw

  raw="$(<"$TEMP_SENSOR")"
  if [[ ! "$raw" =~ ^[0-9]+$ ]]
  then
    return 1
  fi

  printf '%d\n' "$(( (raw + 500) / 1000 ))"
}

interpolate_pwm() {
  local temperature="$1"
  local low_temperature="$2"
  local high_temperature="$3"
  local low_pwm="$4"
  local high_pwm="$5"

  printf '%d\n' "$(( low_pwm + (temperature - low_temperature) * (high_pwm - low_pwm) / (high_temperature - low_temperature) ))"
}

curve_pwm() {
  local temperature="$1"

  if (( temperature <= 55 ))
  then
    printf '%d\n' "$MIN_PWM"
  elif (( temperature <= 60 ))
  then
    interpolate_pwm "$temperature" 55 60 "$MIN_PWM" 64
  elif (( temperature <= 70 ))
  then
    interpolate_pwm "$temperature" 60 70 64 102
  elif (( temperature <= 78 ))
  then
    interpolate_pwm "$temperature" 70 78 102 153
  elif (( temperature <= 85 ))
  then
    interpolate_pwm "$temperature" 78 85 153 204
  elif (( temperature <= 90 ))
  then
    interpolate_pwm "$temperature" 85 90 204 255
  else
    printf '255\n'
  fi
}

apply_pwm() {
  local pwm="$1"
  local current_mode

  current_mode="$(<"$FAN_ENABLE")"
  if [[ "$current_mode" != 1 ]]
  then
    # gpd_fan enters manual mode at full speed for safety; immediately set
    # the calculated value after switching modes.
    set_fan_mode 1
  fi
  printf '%s\n' "$pwm" >"$FAN_PWM"
}

run_controller() {
  local temperature
  local target_pwm
  local last_pwm=""
  local last_change_temperature=""
  local paths_missing_logged=""
  local sensor_missing_logged=""

  trap restore_fan EXIT
  trap 'exit 0' INT TERM

  while true
  do
    if [[ -z "$FAN_PWM" || -z "$FAN_ENABLE" || -z "$TEMP_SENSOR" ]]
    then
      if [[ -z "$paths_missing_logged" ]]
      then
        log_message "waiting for gpdfan and k10temp hwmon devices"
        paths_missing_logged=1
      fi
      set_full_speed
      last_pwm=""
      discover_paths
      sleep "$POLL_SECONDS"
      continue
    fi

    paths_missing_logged=""
    if ! temperature="$(read_temp_c)"
    then
      if [[ -z "$sensor_missing_logged" ]]
      then
        log_message "could not read CPU temperature; using full speed"
        sensor_missing_logged=1
      fi
      set_full_speed
      last_pwm=""
      sleep "$POLL_SECONDS"
      discover_paths
      continue
    fi

    sensor_missing_logged=""
    target_pwm="$(curve_pwm "$temperature")"

    if [[ -z "$last_pwm" ]]
    then
      apply_pwm "$target_pwm"
      log_message "temperature ${temperature}°C -> PWM ${target_pwm}"
      last_pwm="$target_pwm"
      last_change_temperature="$temperature"
    elif (( target_pwm > last_pwm ))
    then
      apply_pwm "$target_pwm"
      log_message "temperature ${temperature}°C -> PWM ${target_pwm}"
      last_pwm="$target_pwm"
      last_change_temperature="$temperature"
    elif (( target_pwm < last_pwm && temperature <= last_change_temperature - HYSTERESIS_C ))
    then
      apply_pwm "$target_pwm"
      log_message "temperature ${temperature}°C -> PWM ${target_pwm}"
      last_pwm="$target_pwm"
      last_change_temperature="$temperature"
    fi

    sleep "$POLL_SECONDS"
    discover_paths
  done
}

main() {
  case "${1:-}" in
    --help|-h)
      usage
      return 0
      ;;
    --safe)
      discover_paths
      set_auto
      return 0
      ;;
    "")
      discover_paths
      run_controller
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
