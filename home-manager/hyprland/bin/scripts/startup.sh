#!/usr/bin/env bash

hyprctl() {
  echo -e "\e[95mRunning 'hyprctl $*'\e[0m" >&2
  command hyprctl "$@"
}

hyprctl::exec() {
  hyprctl dispatch exec -- "$@"
}

hyprctl::sleep-exec() {
  local delay="${1:-1}"
  shift
  local cmd=("$@")

  hyprctl::exec "sh -c 'sleep \"${delay}\"; ${cmd[*]@Q}'"
}

is_nixos() {
  command -v nixos-help &>/dev/null
}

zhj() {
  "${HOME}/bin/zhj" "$@"
}

systemd-unit::is-active() {
  local unit="$1"
  local state
  state="$(systemctl --user is-active "$unit" 2>/dev/null)"

  case "$state" in
    active|activating)
      return 0
      ;;
  esac

  return 1
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

hyprctl::set-cursor-theme() {
  local theme size="${1:-24}"
  theme="$(zhj mouse-cursor::current-theme)"

  if [[ -z "$theme" ]]
  then
    echo "Failed to determine current cursor theme" >&2
    return 1
  fi

  hyprctl setcursor "$theme" "$size"
}

xdg-portal::restart() {
  local u units=(
    xdg-desktop-portal.service
    xdg-desktop-portal-hyprland.service
  )

  for u in "${units[@]}"
  do
    echo "Restarting $u" >&2
    systemctl --user restart "$u"
  done
}

pipewire::restart() {
  systemctl --user restart pipewire pipewire-pulse
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

obs-studio::command() {
  # NOTE order matters here!
  if command -v obs &>/dev/null
  then
    echo obs
    return 0
  fi

  if flatpak list --user --app | grep -q "com.obsproject.Studio"
  then
    echo flatpak run --user com.obsproject.Studio
    return 0
  fi

  return 1
}

obs-studio::version() {
  local obs_cmd
  mapfile -t obs_cmd < <(obs-studio::command)
  # shellcheck disable=SC2068
  ${obs_cmd[@]} --version | awk -F ' - ' '{split($2, a, "."); print a[1]}'
}

# shellcheck disable=SC2120
obs-studio::start() {
  local start_scene="${1:-Joining soon}"
  local obs_args=(--minimize-to-tray --startvirtualcam --scene "$start_scene")
  mapfile -t obs_cmd < <(obs-studio::command)

  # Check if obs >= 30 and disable the shutdown check (and remove the flag in v32)
  local obs_version
  obs_version=$(obs-studio::version)
  if [[ $obs_version -ge 30 && $obs_version -lt 32 ]]
  then
    obs_args+=(--disable-shutdown-check)
  elif [[ $obs_version -ge 32 ]]
  then
    # Remove the sentinel dir ourselves if obs is not running
    if ! pgrep -af "$(command -v "${obs_cmd[*]}")" &>/dev/null
    then
      rm -vrf ~/.config/obs-studio/.sentinel
    fi
  fi

  obs_cmd+=("${obs_args[@]}")

  # Use NVIDIA card explicitly for OBS (if available and only not targeting
  # the flatpak)
  if [[ "${obs_cmd[*]}" == "obs" ]] && \
     [[ -e /dev/dri/card1 ]] && \
     command -v nvidia-offload &>/dev/null
  then
    obs_cmd=(nvidia-offload "${obs_cmd[@]}")
  fi

  # FIXME If we use the nvidia-offload wrapper we might want to do the following:
  # hyprctl::exec "${obs_cmd[*]@Q}"
  hyprctl::exec "systemd-cat --identifier='obs-studio' -- ${obs_cmd[*]}"
  # Update mute status in OBS
  hyprctl::sleep-exec 10 ~/bin/obs.zsh update
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  hyprctl::symlink-dir

  hyprctl::set-cursor-theme 24

  zhj gnome-keyring::auto-unlock

  case "${HOSTNAME:-$(hostname)}" in
    ge2)
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

      obs-studio::start
      ;;
    x13)
      :
      ;;
  esac

  # FIXME This should not be necessary! Pipewire bug?
  # Force (re)start of pipewire
  pipewire::restart

  # Force (re)start of xdg portal
  (sleep 10 && xdg-portal::restart) &

  # Fix gparted & cie
  (sleep 10 && fix-root-gui-apps) &

  # Set DISPLAY and WAYLAND_DISPLAY in tmux session if one already exists.
  if tmux has-session -t main 2>/dev/null
  then
    tmux::set-display-vars
  fi

  # Start terminal
  # shellcheck disable=SC2016
  hyprctl::exec '[workspace 1 silent;] kitty "${HOME}/bin/zhj" tmux::attach'

  # Misc apps
  hyprctl::exec '[workspace 1 silent;] firefox'
  if ! pgrep -af nextcloud &>/dev/null
  then
    hyprctl::exec nextcloud --background
  fi

  # DIRTYFIX Fix for the terminal and firefox being split vertically on startup
  # We want them next to each other
  sleep 5 && "hyprctl dispatch togglesplit" &
  wait
fi
