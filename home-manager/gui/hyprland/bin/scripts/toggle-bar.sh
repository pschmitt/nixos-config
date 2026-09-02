#!/usr/bin/env bash

set -euo pipefail

if systemctl --user is-active --quiet quickshell-bar.service; then
  systemctl --user stop quickshell-bar.service
  systemctl --user start waybar.service
else
  systemctl --user stop waybar.service
  systemctl --user start quickshell-bar.service
fi
