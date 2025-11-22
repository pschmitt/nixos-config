#!/usr/bin/env bash

hyprctl() {
  echo -e "\e[95mRunning 'hyprctl $*'\e[0m" >&2
  command hyprctl "$@"
}

hyprctl::exec() {
  hyprctl dispatch exec -- "$@"
}

is_nixos() {
  command -v nixos-help &>/dev/null
}

zhj() {
  "${HOME}/bin/zhj" "$@"
}

hyprctl::symlink-dir() {
  if [[ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]]
  then
    echo "ERROR: HYPRLAND_INSTANCE_SIGNATURE is not set" >&2
    return 1
  fi

  local dest="${XDG_DATA_HOME:-${HOME}/.local/share}/hyprland"

  rm -rvf "$dest"
  ln -sfv "${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}" "$dest"
}

# https://wiki.archlinux.org/title/Running_GUI_applications_as_root#Using_xhost
fix-root-gui-apps() {
  # This hack seems to only be required on NixOS, on Arch Linux this
  # works out-of-the-box
  if ! is_nixos
  then
    return
  fi

  DISPLAY=${DISPLAY:-:0} xhost si:localuser:root

  # To disable: xhost -si:localuser:root
}

tmux::set-display-vars() {
  tmux set-environment DISPLAY "$DISPLAY"
  tmux set-environment WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
  # Set WAYLAND_DISPLAY for zsh sessions that were started before hyprland
  # See $ZDOTDIR/ztraps
  killall -USR2 zsh
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  hyprctl::symlink-dir

  # Set DISPLAY and WAYLAND_DISPLAY in tmux session if one already exists.
  if tmux has-session -t main 2>/dev/null
  then
    tmux::set-display-vars
  fi

  # DIRTYFIX Workaround for gnome-keyring not auto-unlocking on hyprland startup
  zhj gnome-keyring::auto-unlock

  # Fix gparted & cie
  (sleep 10 && fix-root-gui-apps) &

  FIREFOX_WORKSPACE=2
  case "${HOSTNAME:-$(hostname)}" in
    ge2)
      FIREFOX_WORKSPACE=1
      TOGGLE_SPLIT=1
      # NOTE hyprctl refuses to parse batch commands that contain newlines
      hyprctl --batch "\
        dispatch moveworkspacetomonitor 1 desc:LG; \
        dispatch moveworkspacetomonitor 2 desc:Lenovo; \
        dispatch focusmonitor desc:Lenovo; \
        dispatch workspace 2; \
        dispatch focusmonitor desc:LG; \
        dispatch workspace 1;"

      # Mute default mic
      zhj pulseaudio::mute-default-source
      ;;
  esac

  # Start terminal
  # shellcheck disable=SC2016
  hyprctl::exec '[workspace 1 silent;] kitty "${HOME}/bin/zhj" tmux::attach'

  # Start browser
  hyprctl::exec "[workspace $FIREFOX_WORKSPACE silent;] firefox"

  # DIRTYFIX Fix for the terminal and firefox being split vertically on startup
  # We want them next to each other (ge2 only)
  if [[ -n $TOGGLE_SPLIT ]]
  then
    (sleep 5 && hyprctl dispatch togglesplit) &
  fi

  [[ -n $WAIT ]] && wait
fi
