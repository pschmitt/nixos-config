#!/usr/bin/env bash

is_nixos() {
  grep -qE 'ID="?nixos"?' /etc/os-release &>/dev/null
}

nixos::get-gi-typelib-path() {
  local playerctl
  playerctl="$(command -v "playerctl")"

  if [[ -z "$playerctl" ]]
  then
    echo "Failed to determine path to playerctl binary" >&2
    return 1
  fi

  local store_path
  store_path=$(readlink -f $playerctl | cut -d '/' -f -4)

  if [[ -z "$store_path" ]]
  then
    echo "Failed to determine store path of playerctl" >&2
    return 1
  fi

  local typelib_path="${store_path}/lib/girepository-1.0"
  if [[ ! -d "$typelib_path" ]]
  then
    echo "$typelib_path does not exist sadly." >&2
    return 1
  fi

  echo "$typelib_path"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  if is_nixos
  then
    GI_TYPELIB_PATH="$(nixos::get-gi-typelib-path)"
    if [[ -n "$GI_TYPELIB_PATH" ]]
    then
      export GI_TYPELIB_PATH
    fi
  fi

  ./mediaplayer.py "$@"
fi
