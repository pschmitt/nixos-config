#!/usr/bin/env bash

hyprctl::get-current-ws() {
  # This would return something like "[4,2,1]" if you have 3 monitors
  hyprctl monitors -j | \
    jq -er '[.[].activeWorkspace.id]'
}

hyprctl::clients-on-ws() {
  local ws="${1:-$(hyprctl::get-current-ws)}"
  local clients="${2:-$(hyprctl clients -j)}"

  jq -er --argjson ws "$ws" \
    'map(select(.workspace.id as $current_ws | any($ws[]; . == $current_ws)))' \
    <<< "$clients"
}

hyprctl::clients-on-current-ws() {
  hyprctl::clients-on-ws "$(hyprctl::get-current-ws)" "$@"
}

hyprctl::slurp-rects() {
  local clients="${1:-$(hyprctl::clients-on-current-ws)}"

  jq -er '.[] | "\(.at[0]), \(.at[1]) \(.size[0])x\(.size[1])"' \
    <<< "$clients"
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  CLIENTS="$(hyprctl clients -j)"
  CLIENTS_ON_WS="$(hyprctl::clients-on-current-ws "$CLIENTS")"

  case "$(jq -er 'length' <<< "$CLIENTS_ON_WS")" in
    0)
      echo "No clients on current workspace." >&2
      exit 1
      ;;
    1)
      jq -er <<< "$CLIENTS_ON_WS"
      exit 0
      ;;
  esac

  SLURP_RECTS="$(hyprctl::slurp-rects "$CLIENTS_ON_WS")"

  SELECTED_CLIENT="$(slurp -r <<< "$SLURP_RECTS")"

  if [[ -z "$SELECTED_CLIENT" ]]
  then
    echo "No client/window selected. Aborted by user." >&2
    exit 1
  fi

  read -r CLIENT_X CLIENT_Y CLIENT_WIDTH CLIENT_HEIGHT \
    < <(awk -F'[, x]' '{ print $1, $2, $3, $4 }' <<< "$SELECTED_CLIENT")

  {
    echo "Selected client: $SELECTED_CLIENT"
    echo "Client X:      $CLIENT_X"
    echo "Client Y:      $CLIENT_Y"
    echo "Client Width:  $CLIENT_WIDTH"
    echo "Client Height: $CLIENT_HEIGHT"
  } >&2

  jq -er \
    --argjson x "$CLIENT_X" \
    --argjson y "$CLIENT_Y" \
    --argjson w "$CLIENT_WIDTH" \
    --argjson h "$CLIENT_HEIGHT" \
     '.[] | select(
        .at[0] == $x and
        .at[1] == $y and
        .size[0] == $w and
        .size[1] == $h)' \
    <<< "$CLIENTS_ON_WS"
fi
