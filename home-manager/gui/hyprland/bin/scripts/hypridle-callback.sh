#!/usr/bin/env bash

# Add the sudo wrapper to path
export PATH="/run/wrappers/bin:${HOME}/bin:${PATH}"

notify() {
  notify-send -a hypridle "$@"
}

gcr-unlock() {
  # Trigger the gnome-keyring-auto-unlock service (sops-backed on ge2,
  # zhj fallback elsewhere) rather than calling zhj directly.
  systemctl --user start gnome-keyring-auto-unlock.service
}

lock() {
  "${HOME}/.config/hypr/bin/lock.sh" "$@"
}

unlock() {
  zhj lockscreen::off
}

ACTION="$1"
shift

# notify "Hypridle callback: $ACTION"

case "$ACTION" in
  resume|after-sleep)
    gcr-unlock
    # NOTE This should fix the issue where zsh hangs forever because of
    # the /mnt/ha mount
    sudo systemctl restart netbird-netbird-io
    ;;
  sleep|before-sleep)
    lock --now
    ;;
  lock|timeout|on-timeout)
    lock --now
    ;;
  unlock|on-unlock)
    # NOTE calling gcr-unlock here might be redundant, since
    # unlocking the screen (via unlock) will trigger the another hypridle event,
    # maybe even the same?
    gcr-unlock
    # unlock
    ;;
  activity|on-resume)
    gcr-unlock
    ;;
  *)
    notify "Hypridle unknown action: $ACTION"
    exit 2
    ;;
esac
