{ inputs, pkgs, ... }:
{
  # One-shot checker
  systemd.services.rpi-power = {
    description = "Log Raspberry Pi power/throttle flags (vcgencmd get_throttled)";
    serviceConfig = {
      Type = "oneshot";
    };

    # Add vcgencmd to PATH just for this service
    path = [
      inputs.nixos-raspberrypi.packages.${stdenv.hostPlatform.system}.raspberrypi-utils
      pkgs.coreutils
    ];

    script = ''
      # vcgencmd outputs: throttled=0xXXXXXXXX
      OUT="$(vcgencmd get_throttled)"
      HEX="''${OUT#*=}"
      HEX="''${HEX#0x}"

      if [[ -z "$HEX" ]]
      then
        echo "Failed to parse 'vcgencmd get_throttled' output: '$OUT'" >&2
        exit 1
      fi

      DATA=$((16#$HEX))
      echo "OUT='$OUT' HEX='$HEX' DATA='$DATA'"

      report() {
        local val="$1"
        local bit="$2"
        local msg="$3"

        local status="no"
        if [[ $(( val & (1 << bit) )) -ne 0 ]]
        then
          status="YES!"
        fi

        echo "$msg: $status"
      }

      report "$DATA" 0  "under-voltage now"
      report "$DATA" 16 "under-voltage has occurred"
      report "$DATA" 1  "freq capped now"
      report "$DATA" 17 "freq capped has occurred"
      report "$DATA" 2  "throttled now"
      report "$DATA" 18 "throttling has occurred"
      report "$DATA" 3  "soft temp limit now"
      report "$DATA" 19 "soft temp limit has occurred"
    '';
  };

  systemd.timers.rpi-power = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
    };
  };
}
