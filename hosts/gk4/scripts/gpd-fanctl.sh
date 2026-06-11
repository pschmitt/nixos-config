# gpd-fanctl — control the GPD Pocket fan via the gpd_fan hwmon interface.
#
# Wrapped by writeShellApplication: shebang, `set -euo pipefail` and PATH
# (coreutils via runtimeInputs) are injected by Nix. `sudo` is resolved from
# the system profile so the setuid wrapper is used.

usage() {
  cat <<EOF
Usage: $(basename "$0") [auto|manual|off] [value]
  auto    → let EC/kernel manage fan
  manual  → set manual mode; requires [value] 0-255
  off     → disable control (fan full speed)
  *       → show current RPM
EOF
}

main() {
  local hwmon_base=/sys/devices/platform/gpd_fan/hwmon
  local hwmon_dir
  local quiet=""
  local action

  shopt -s nullglob
  local hwmon_dirs=("$hwmon_base"/hwmon*)
  shopt -u nullglob
  hwmon_dir="${hwmon_dirs[0]:-}"

  if [[ -z "$hwmon_dir" ]]
  then
    echo "gpd_fan hwmon device not found" >&2
    return 2
  fi

  while [[ -n "$*" ]]
  do
    case "$1" in
      -h|--help|-\?)
        usage
        return 0
        ;;
      -q|--quiet)
        quiet=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  action="${1:-}"

  case "$action" in
    auto)
      echo 2 | sudo tee "${hwmon_dir}/pwm1_enable"
      ;;
    manual)
      if [[ -z "${2:-}" ]] || [[ "$2" -lt 0 ]] || [[ "$2" -gt 255 ]]
      then
        echo "Need value 0-255" >&2
        return 2
      fi
      echo 1 | sudo tee "${hwmon_dir}/pwm1_enable"
      echo "$2" | sudo tee "${hwmon_dir}/pwm1"
      ;;
    off)
      echo 0 | sudo tee "${hwmon_dir}/pwm1_enable"
      ;;
    *)
      if [[ -z "$quiet" ]]
      then
        echo -n "Current RPM: "
      fi
      cat "$hwmon_dir/fan1_input"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
