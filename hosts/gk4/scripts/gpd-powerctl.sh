# gpd-powerctl — manage GPD Pocket 4 power profiles and fan control.

usage() {
  cat <<EOF
Usage: $(basename "$0") COMMAND [ARGUMENT]

Commands:
  status
  profile <power-saver|balanced|performance>
  fan status
  fan curve
  fan auto
  fan full
  fan manual <0-255>
EOF
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

write_sysfs() {
  local value="$1"
  local file="$2"

  if [[ "$EUID" -eq 0 ]]
  then
    printf '%s\n' "$value" >"$file"
  else
    printf '%s\n' "$value" | sudo tee "$file" >/dev/null
  fi
}

fan_paths() {
  local fan_hwmon

  fan_hwmon="$(find_hwmon gpdfan || true)"
  if [[ -z "$fan_hwmon" || ! -e "$fan_hwmon/pwm1" || ! -e "$fan_hwmon/pwm1_enable" ]]
  then
    echo "gpdfan hwmon device not found" >&2
    return 1
  fi

  FAN_PWM="$fan_hwmon/pwm1"
  FAN_ENABLE="$fan_hwmon/pwm1_enable"
  FAN_RPM="$fan_hwmon/fan1_input"
}

stop_curve() {
  if systemctl is-active --quiet gpd-fan-curve.service
  then
    sudo systemctl stop gpd-fan-curve.service
  fi
}

fan_status() {
  local fan_hwmon
  local cpu_hwmon
  local profile
  local tdp_info

  fan_paths
  fan_hwmon="$(find_hwmon gpdfan)"
  cpu_hwmon="$(find_hwmon k10temp || true)"
  profile="$(powerprofilesctl get)"

  printf 'Power profile: %s\n' "$profile"
  printf 'Fan curve service: %s\n' "$(systemctl is-active gpd-fan-curve.service || true)"
  printf 'Fan mode: %s\n' "$(<"$FAN_ENABLE")"
  printf 'Fan PWM: %s\n' "$(<"$FAN_PWM")"
  printf 'Fan RPM: %s\n' "$(<"$FAN_RPM")"
  if [[ -n "$cpu_hwmon" && -r "$cpu_hwmon/temp1_input" ]]
  then
    printf 'CPU Tctl: %s°C\n' "$(( ( $(<"$cpu_hwmon/temp1_input") + 500 ) / 1000 ))"
  fi

  if tdp_info="$(sudo -n ryzenadj-tdp --info 2>/dev/null)"
  then
    printf '%s\n' 'TDP limits:'
    while IFS= read -r line
    do
      case "$line" in
        *LIMIT*)
          printf '  %s\n' "$line"
          ;;
      esac
    done <<<"$tdp_info"
  else
    printf '%s\n' 'TDP limits: unavailable without sudo authentication'
  fi
}

set_fan() {
  local action="$1"
  local value="${2:-}"

  fan_paths
  stop_curve

  case "$action" in
    auto)
      write_sysfs 2 "$FAN_ENABLE"
      ;;
    full)
      write_sysfs 0 "$FAN_ENABLE"
      ;;
    manual)
      if [[ ! "$value" =~ ^[0-9]+$ || "$value" -gt 255 ]]
      then
        echo 'Manual PWM must be between 0 and 255' >&2
        return 2
      fi
      write_sysfs 1 "$FAN_ENABLE"
      write_sysfs "$value" "$FAN_PWM"
      ;;
    curve)
      sudo systemctl restart gpd-fan-curve.service
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    status)
      fan_status
      ;;
    profile)
      if [[ "$#" -ne 2 ]]
      then
        usage >&2
        return 2
      fi
      case "$2" in
        power-saver|balanced|performance)
          powerprofilesctl set "$2"
          ;;
        *)
          echo "Unsupported power profile: $2" >&2
          return 2
          ;;
      esac
      ;;
    fan)
      case "${2:-}" in
        status)
          fan_status
          ;;
        curve|auto|full)
          set_fan "$2"
          ;;
        manual)
          if [[ "$#" -ne 3 ]]
          then
            usage >&2
            return 2
          fi
          set_fan manual "$3"
          ;;
        *)
          usage >&2
          return 2
          ;;
      esac
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
