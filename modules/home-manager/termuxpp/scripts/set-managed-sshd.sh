#!/system/bin/sh
# Tasker launcher: start or stop the guest sshd (Home Assistant's "sshd
# Intent: START/STOP"). It only drives the guest's runit service through svc,
# so there is one sshd, supervised, and services.sshd.allowedSsids applies.
set -eu

case "${1:-}" in
  start|stop|restart)
    # nixpp login is the one entry from the native side into the guest.
    # shellcheck disable=SC2016 # expands in the guest shell
    exec "${PREFIX:-/data/data/dev.pschmitt.termux/files/usr}/bin/nixpp" login -c \
      'exec /run/current-system/sw/bin/svc "$1" sshd' set-managed-sshd "$1"
    ;;
  *)
    printf 'Usage: %s start|stop|restart\n' "$0" >&2
    exit 2
    ;;
esac

# vim: set ft=sh et ts=2 sw=2 :
