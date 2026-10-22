#!/usr/bin/env bash
# Run hypruse against the running Hyprland session. Environment handed down by
# the caller wins; whatever is missing (an SSH or system-service context has no
# compositor env) is discovered from the runtime dir.

shopt -s nullglob

export HYPRUSE_AUTH_GUARD="${HYPRUSE_AUTH_GUARD:-strict}"
export HYPRUSE_STRICT="${HYPRUSE_STRICT:-1}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
then
  newest=""
  for dir in "$XDG_RUNTIME_DIR"/hypr/*/
  do
    [[ -S ${dir}.socket.sock ]] || continue
    if [[ -z "$newest" || ${dir}.socket.sock -nt ${newest}.socket.sock ]]
    then
      newest="$dir"
    fi
  done

  if [[ -z "$newest" ]]
  then
    echo "No running Hyprland instance in $XDG_RUNTIME_DIR/hypr" >&2
    exit 1
  fi

  newest="${newest%/}"
  export HYPRLAND_INSTANCE_SIGNATURE="${newest##*/}"
fi

if [[ -z "${WAYLAND_DISPLAY:-}" ]]
then
  for sock in "$XDG_RUNTIME_DIR"/wayland-*
  do
    [[ -S $sock ]] || continue
    export WAYLAND_DISPLAY="${sock##*/}"
    break
  done
fi

exec hypruse "$@"
