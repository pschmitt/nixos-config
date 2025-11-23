#!/usr/bin/env bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

hyprctl() {
  echo "DEBUG: \$ hyprctl $*" >&2
  command hyprctl "$@"
}

get_mod_key() {
  local key
  key="$(awk -F ' *= *' '/\$mod *= */ {print $2 }' "${CONFIG_DIR}/config.d/keys.conf")"
  key=${key:-SUPER}
  echo "$key"
}

update_key() {
  local key="$1" value="$2"
  local mod="${MOD:-$(get_mod_key)}"

  # Replace $mod with the actual mod key
  # shellcheck disable=SC2001
  key=$(sed "s#\$mod#${mod}#I" <<< "$key")

  hyprctl --batch "keyword unbind $key; keyword bind $key, $value;"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  MOD="$(get_mod_key)"

  update_key "$@"
fi
