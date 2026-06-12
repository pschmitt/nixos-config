# Self-contained Timewarrior status helpers, replacing the zhj/zsh
# `timewarrior::is-on` and `timewarrior::summary` functions.
{
  symlinkJoin,
  writeShellApplication,
  timewarrior,
  jq,
  gnugrep,
}:
let
  timew-is-on = writeShellApplication {
    name = "timew-is-on";
    runtimeInputs = [
      timewarrior
      gnugrep
    ];
    # Exit 0 when Timewarrior is actively tracking, non-zero otherwise.
    # Default the DB location so this works outside the interactive shell
    # (e.g. the waybar / go-hass-agent systemd services), where TIMEWARRIORDB
    # would otherwise be unset and timew would read an empty default DB.
    text = ''
      export TIMEWARRIORDB="''${TIMEWARRIORDB:-$HOME/.config/timewarrior}"
      timew | grep -vq 'no active time tracking'
    '';
  };

  timew-total = writeShellApplication {
    name = "timew-total";
    runtimeInputs = [
      timewarrior
      jq
    ];
    # Total tracked time for a timeframe (default: today).
    #   -s/--seconds, -r/--raw : raw seconds
    #   -H/--hours             : fractional hours (%.5f)
    #   -M/--minutes           : H:MM
    #   (default)              : H:MM:SS
    text = ''
      export TIMEWARRIORDB="''${TIMEWARRIORDB:-$HOME/.config/timewarrior}"
      raw=0 hours=0 minutes=0
      while [[ $# -gt 0 ]]
      do
        case "$1" in
          -r|--raw|-s|--seconds) raw=1; shift ;;
          -H|--hours) hours=1; shift ;;
          -M|--minutes) minutes=1; shift ;;
          --) shift; break ;;
          -*) echo "Unknown option: $1" >&2; exit 2 ;;
          *) break ;;
        esac
      done

      timeframe="''${1:-today}"
      case "$timeframe" in
        *tod*) timeframe="today" ;;
        :*) ;;
        *) timeframe=":''${timeframe}" ;;
      esac

      data="$(timew export "$timeframe")"

      if jq -e 'length == 0' <<< "$data" >/dev/null
      then
        echo "No data found for '$timeframe'" >&2
        exit 1
      fi

      res="$(TZ=UTC jq -er --arg tf "%Y%m%dT%H%M%SZ" '[
          map({
            start: .start | strptime($tf) | mktime,
            end: (try (.end | strptime($tf) | mktime) catch (now | round))
          }) | .[] | (.end - .start)
        ] | add' <<< "$data")"

      if [[ -z "$res" ]]
      then
        echo "Failed to retrieve total time for '$timeframe'" >&2
        exit 1
      fi

      if [[ "$res" == "null" ]]
      then
        res=0
      fi

      if [[ "$raw" -eq 1 ]]
      then
        echo "$res"
        exit 0
      fi

      if [[ "$hours" -eq 1 ]]
      then
        awk -v r="$res" 'BEGIN { printf "%.5f\n", r / 3600 }'
        exit 0
      fi

      if [[ "$minutes" -eq 1 ]]
      then
        printf '%d:%02d\n' "$(( res / 3600 ))" "$(( res % 3600 / 60 ))"
        exit 0
      fi

      printf '%d:%02d:%02d\n' "$(( res / 3600 ))" "$(( res % 3600 / 60 ))" "$(( res % 60 ))"
    '';
  };
in
symlinkJoin {
  name = "timew-status";
  paths = [
    timew-is-on
    timew-total
  ];
}
