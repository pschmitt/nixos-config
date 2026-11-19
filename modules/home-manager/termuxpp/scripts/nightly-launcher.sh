#!/system/bin/sh
set -eu

unlock() {
  if [ "$wake_locked" = 1 ]
  then
    timeout 10 termux-wake-unlock >/dev/null 2>&1 || :
  fi
}

main() {
  wake_locked=0
  if command -v termux-wake-lock >/dev/null && timeout 15 termux-wake-lock >/dev/null
  then
    wake_locked=1
  fi
  trap unlock EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  # nixpp login is the one entry from the native side into the guest.
  # shellcheck disable=SC2016 # expands in the guest shell
  "${PREFIX:-/data/data/dev.pschmitt.termux/files/usr}/bin/nixpp" login -c \
    'exec "$HOME/.nix-profile/bin/termuxpp-nightly-update" "$@"' termuxpp-nightly "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
