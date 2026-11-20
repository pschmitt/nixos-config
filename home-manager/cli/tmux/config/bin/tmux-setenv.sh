#!/usr/bin/env bash

TMPDIR=${TMPDIR:-/tmp}
XDG_CONFIG_HOME=${XDG_DATA_HOME:-${HOME}/.config}
XDG_DATA_HOME=${XDG_DATA_HOME:-${HOME}/.local/share}

tmux_export() {
  local var="$1"
  local value="$2"

  echo tmux setenv -g "$var" "$value"
}

tmux_xdg_exports() {
  tmux_export TMPDIR "${TMPDIR:-/tmp}"
  tmux_export XDG_CONFIG_HOME "$XDG_CONFIG_HOME"
  tmux_export XDG_DATA_HOME "$XDG_DATA_HOME"
}

tmux_custom_exports() {
  TMUX_CONFIG_HOME="${XDG_CONFIG_HOME}/tmux"
  tmux_export TMUX_CONFIG_HOME "$TMUX_CONFIG_HOME"
  tmux_export TMUX_BIN_HOME "${TMUX_CONFIG_HOME}/bin"
  tmux_export TMUX_PLUGIN_MANAGER_PATH "${XDG_DATA_HOME}/tpm"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  tmux_xdg_exports
  tmux_custom_exports
fi
