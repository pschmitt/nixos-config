{
  writeShellApplication,
  timewarrior,
  jq,
  coreutils,
}:
writeShellApplication {
  name = "timew-week-breakdown";
  runtimeInputs = [
    timewarrior
    jq
    coreutils
  ];
  # Per-day totals for a timeframe (default: this week), one line per day
  # that has tracked time: "YYYY-MM-DD\t<Dow>\tH:MM", oldest first.
  text = ''
    export TIMEWARRIORDB="''${TIMEWARRIORDB:-$HOME/.config/timewarrior}"
    timeframe="''${1:-:week}"
    case "$timeframe" in
      :*) ;;
      *) timeframe=":''${timeframe}" ;;
    esac

    data="$(timew export "$timeframe")"

    if jq -e 'length == 0' <<< "$data" >/dev/null
    then
      exit 0
    fi

    # Resolve start/end to UTC epoch seconds in jq (as timew-total does),
    # then group by local calendar day via `date`, since jq has no TZ database.
    pairs="$(TZ=UTC jq -er --arg tf "%Y%m%dT%H%M%SZ" '
        .[] | [
          (.start | strptime($tf) | mktime),
          (try (.end | strptime($tf) | mktime) catch (now | round))
        ] | @tsv
      ' <<< "$data")"

    declare -A day_seconds
    while IFS=$'\t' read -r start_epoch end_epoch
    do
      [[ -z "$start_epoch" ]] && continue
      day_key="$(date -d "@$start_epoch" +%Y-%m-%d)"
      day_seconds["$day_key"]=$(( ''${day_seconds["$day_key"]:-0} + end_epoch - start_epoch ))
    done <<< "$pairs"

    for day in "''${!day_seconds[@]}"
    do
      secs="''${day_seconds[$day]}"
      dow="$(date -d "$day" +%a)"
      printf '%s\t%s\t%d:%02d\n' "$day" "$dow" "$(( secs / 3600 ))" "$(( secs % 3600 / 60 ))"
    done | sort
  '';
}
