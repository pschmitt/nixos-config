# shellcheck shell=bash
main() {
  local threshold
  local output
  local temp_c
  local hot

  threshold="${1:-90}"

  output=$(sensors -j | jq -r --argjson t "$threshold" '
    [ to_entries[] |
      .key as $chip |
      .value | to_entries[] |
      select(.value | type == "object") |
      .key as $sensor |
      .value | to_entries[] |
      select(.key | endswith("_input")) |
      { name: "\($chip)/\($sensor)", temp: (.value | floor) }
    ] as $all |
    "\(($all | map(.temp) | max))|\($all | map(select(.temp > $t)) | map("\(.name)=\(.temp)°C") | join(", "))"
  ')

  temp_c=${output%%|*}
  hot=${output#*|}

  if [[ -z "$temp_c" || "$temp_c" == "null" ]]
  then
    printf 'ERROR: Could not read thermal sensors\n' >&2
    return 1
  fi

  printf 'Thermal check: %d°C\n' "$temp_c"

  if [[ -n "$hot" ]]
  then
    printf 'WARNING: sensors above threshold (%d°C): %s\n' "$threshold" "$hot" >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
