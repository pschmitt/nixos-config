#!/usr/bin/env bash

hyprctl() {
  echo -e "\e[95mRunning 'hyprctl $*'\e[0m" >&2
  command hyprctl "$@"
}

hyprctl::exec() {
  hyprctl dispatch exec -- "$@"
}

has() {
  command -v "$1" &>/dev/null
}

foot-server() {
  if pgrep -af "foot --server" &>/dev/null
  then
    return
  fi

  notify-send 'Spawning "foot --server"...'
  hyprctl::exec foot --server
  sleep 2
}

terminal::detect() {
  # NOTE Order matters here!
  local apps=(
    kitty
    ghostty
    wezterm
    wezterm-nightly
    foot
    alacritty
    konsole
    gnome-terminal
    xterm
  )

  local a
  for a in "${apps[@]}"
  do
    if has "$a"
    then
      echo "$a"
      return 0
    fi
  done

  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  TERMINAL="$(terminal::detect)"

  if [[ -z "$TERMINAL" ]]
  then
    notify-send -u critical "SHITE: No terminal available"
    exit 1
  fi

  case "$TERMINAL" in
    foot)
      foot-server
      exec footclient
      ;;
    *)
      exec "$TERMINAL"
      ;;
  esac
fi
