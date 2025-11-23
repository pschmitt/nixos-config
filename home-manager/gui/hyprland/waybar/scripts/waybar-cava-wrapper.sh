#!/usr/bin/env bash

get_default_source() {
  zhj pulseaudio::get-default-source
}

write_cava_config() {
  local dest="${XDG_CONFIG_HOME:-${HOME}/.config}/waybar/cava.config"
  local default_source
  default_source="$(get_default_source)"

  rm -f "$dest"

  cat <<EOF > "$dest"
[input]
method = pulse
source = $default_source
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  write_cava_config

  exec waybar "$@"
fi
