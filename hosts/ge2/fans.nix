{ pkgs, ... }:

let
  dellFans = pkgs.writeShellApplication {
    name = "dell-fans";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
    ];
    text = ''
      set -euo pipefail

      HW_PATH=""
      PLATFORM_PROFILE="/sys/firmware/acpi/platform_profile"
      PROFILE_CHOICES="/sys/firmware/acpi/platform_profile_choices"

      usage() {
        cat <<'USAGE'
      Usage: dell-fans [command]

      Commands:
        status                       Show platform profile, temps and RPMs
        profile <mode>               Set platform profile (cool|quiet|balanced|performance)
        set <value>                  Force both fans to PWM value (0-255)
        set <fan1|fan2> <value>      Force one fan to PWM value (0-255)
      USAGE
      }

      need_hwmon() {
        if [[ -n "$HW_PATH" ]]; then
          return
        fi
        for d in /sys/class/hwmon/hwmon*/; do
          [[ -f "''${d}name" ]] || continue
          if [[ $(<"''${d}name") == "dell_smm" ]]; then
            HW_PATH=''${d%/}
            break
          fi
        done
        if [[ -z "$HW_PATH" ]]; then
          echo "dell_smm hwmon device not found" >&2
          exit 1
        fi
      }

      write_sys() {
        local value=$1 file=$2
        if [[ $EUID -eq 0 ]]; then
          printf '%s\n' "$value" > "$file"
        else
          printf '%s\n' "$value" | sudo tee "$file" > /dev/null
        fi
      }

      set_pwm() {
        local fan=$1 value=$2
        need_hwmon
        if ! [[ $value =~ ^[0-9]+$ && $value -ge 0 && $value -le 255 ]]; then
          echo "PWM value must be between 0 and 255" >&2
          exit 1
        fi
        local file="$HW_PATH/pwm$fan"
        write_sys "$value" "$file"
        local readback
        readback=$(<"$file")
        if [[ $readback != "$value" ]]; then
          echo "Warning: firmware reset pwm$fan back to $readback (manual control likely disabled)" >&2
          return 1
        fi
      }

      set_profile() {
        local mode=$1
        if [[ ! -e $PLATFORM_PROFILE ]]; then
          echo "Platform profile interface unavailable" >&2
          exit 1
        fi
        if [[ -r $PROFILE_CHOICES ]]; then
          local choices
          choices=$(<"$PROFILE_CHOICES")
          if ! grep -qw -- "$mode" <<< "$choices"; then
            echo "Mode '$mode' not in: $choices" >&2
            exit 1
          fi
        fi
        write_sys "$mode" "$PLATFORM_PROFILE"
      }

      status() {
        need_hwmon
        if [[ -r $PLATFORM_PROFILE ]]; then
          printf "Platform profile: %s\n" "$(<"$PLATFORM_PROFILE")"
        fi
        printf "\nFans (RPM):\n"
        for fan in "$HW_PATH"/fan*_input; do
          [[ -r $fan ]] || continue
          printf "  %s: %s\n" "$(basename "$fan")" "$(<"$fan")"
        done
        printf "\nPWM values:\n"
        for pwm in "$HW_PATH"/pwm*; do
          [[ -r $pwm ]] || continue
          printf "  %s: %s\n" "$(basename "$pwm")" "$(<"$pwm")"
        done
      }

      main() {
        local cmd=''${1:-status}
        case $cmd in
          status)
            status
            ;;
          profile)
            [[ $# -ge 2 ]] || { usage >&2; exit 1; }
            set_profile "$2"
            ;;
          set)
            if [[ $# -eq 2 ]]; then
              set_pwm 1 "$2"
              set_pwm 2 "$2"
            elif [[ $# -eq 3 ]]; then
              case $2 in
                fan1|1) set_pwm 1 "$3" ;;
                fan2|2) set_pwm 2 "$3" ;;
                *)
                  echo "Unknown fan '$2'" >&2
                  exit 1
                  ;;
              esac
            else
              usage >&2
              exit 1
            fi
            ;;
          -h|--help|help)
            usage
            ;;
          *)
            usage >&2
            exit 1
            ;;
        esac
      }

      main "$@"
    '';
  };
in
{
  environment.systemPackages = [ dellFans ];
}
