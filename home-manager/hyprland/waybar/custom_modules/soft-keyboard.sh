#!/usr/bin/env bash

set -euo pipefail

schema="org.gnome.desktop.a11y.applications"
key="screen-keyboard-enabled"

is_enabled() {
  [[ "$(gsettings get "${schema}" "${key}")" == "true" ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    format)
      if is_enabled; then
        icon=""
        alt="enabled"
        class="custom-soft-keyboard enabled"
        tooltip="On-screen keyboard enabled"
      else
        icon=""
        alt="disabled"
        class="custom-soft-keyboard disabled"
        tooltip="On-screen keyboard disabled"
      fi

      jq -ernc \
        --arg icon "${icon}" \
        --arg class "${class}" \
        --arg alt "${alt}" \
        --arg tooltip "${tooltip}" \
        '{
          "text": $icon,
          "class": $class,
          "alt": $alt,
          "tooltip": $tooltip
        }'
      ;;
  esac
fi
