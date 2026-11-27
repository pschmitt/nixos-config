#!/system/bin/sh
set -eu

# Tasker runs this natively. Everything else happens in the guest, which also
# takes the wake lock (tpp wake-lock) while its maintenance runs; nothing here
# needs the Termux prefix beyond nixpp.
# shellcheck disable=SC2016 # expands in the guest shell
exec "${PREFIX:-/data/data/dev.pschmitt.termux/files/usr}/bin/nixpp" login -c \
  'exec "$HOME/.nix-profile/bin/termuxpp-nightly-update" "$@"' termuxpp-nightly "$@"

# vim: set ft=sh et ts=2 sw=2 :
