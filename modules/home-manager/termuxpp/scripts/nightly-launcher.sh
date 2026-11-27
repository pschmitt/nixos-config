#!/system/bin/sh
set -eu

# Tasker waits this long for the whole job.
BUDGET=3600
# The native package upgrade needs at least this much of it.
NATIVE_MIN=600

unlock() {
  if [ "$wake_locked" = 1 ]
  then
    timeout 10 termux-wake-unlock >/dev/null 2>&1 || :
  fi
}

# Upgrade the upstream Termux packages of the native prefix with apt, the way
# `pkg upgrade` would, unattended: existing configuration files stay. TermuxPP's
# own packages (nixpp, rbw: the fork) are held; generations update their files.
native_upgrade() {
  prefix=${PREFIX:-/data/data/dev.pschmitt.termux/files/usr}
  runtime=${HOME:-/data/data/dev.pschmitt.termux/files/home}/.local/share/termuxpp-nix
  # Upstream binaries need the path redirect the app's shells preload.
  if [ -z "${TERMUX_PKG_REDIRECT_SO:-}" ] && [ -r "$runtime/apk-library" ]
  then
    IFS= read -r redirect < "$runtime/apk-library" || redirect=
    if [ -n "$redirect" ] && [ -r "$redirect" ]
    then
      export TERMUX_PKG_REDIRECT_SO="$redirect" LD_PRELOAD="$redirect"
      export LD_LIBRARY_PATH="$prefix/lib"
      if [ -r "$prefix/lib/libtermux-exec.so" ]
      then
        export LD_PRELOAD="$LD_PRELOAD:$prefix/lib/libtermux-exec.so"
      fi
    fi
  fi
  export PATH="$prefix/bin:/system/bin" DEBIAN_FRONTEND=noninteractive
  for package in nixpp rbw
  do
    if "$prefix/bin/dpkg" -s "$package" >/dev/null 2>&1
    then
      "$prefix/bin/apt-mark" hold "$package" >/dev/null || return 1
    fi
  done
  timeout 300 "$prefix/bin/apt-get" -q update || return 1
  timeout "$1" "$prefix/bin/apt-get" -q -y \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    full-upgrade
}

main() {
  started=$(date +%s)
  wake_locked=0
  if command -v termux-wake-lock >/dev/null && timeout 15 termux-wake-lock >/dev/null
  then
    wake_locked=1
  fi
  trap unlock EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  # nixpp login is the one entry from the native side into the guest.
  status=0
  # shellcheck disable=SC2016 # expands in the guest shell
  "${PREFIX:-/data/data/dev.pschmitt.termux/files/usr}/bin/nixpp" login -c \
    'exec "$HOME/.nix-profile/bin/termuxpp-nightly-update" "$@"' termuxpp-nightly "$@" || status=$?

  # The guest job asks for the native upgrade when its maintenance ran (on
  # Wi-Fi, charging). Its state directory, from the native side:
  runtime=${HOME:-/data/data/dev.pschmitt.termux/files/home}/.local/share/termuxpp-nix
  home=$(sed -n 's/^SESSION_HOME=//p' "$runtime/session.env" 2>/dev/null) || home=
  state=$runtime/root${home:-/nonexistent}/.local/state/termuxpp-nightly
  [ -e "$state/native-upgrade.request" ] || return "$status"
  rm -f -- "$state/native-upgrade.request"
  left=$((BUDGET - ($(date +%s) - started) - 60))
  if [ "$left" -lt "$NATIVE_MIN" ]
  then
    printf '%s Not enough time left for the native package upgrade.\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" >> "$state/last-run.log"
    printf 'Native packages: skipped (no time left)\n'
    return "$status"
  fi
  printf '%s Starting native package upgrade\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" >> "$state/last-run.log"
  native=0
  native_upgrade "$left" >> "$state/last-run.log" 2>&1 || native=$?
  printf '%s Finished native package upgrade (exit %s)\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$native" >> "$state/last-run.log"
  if [ "$native" = 0 ]
  then
    printf 'Native packages: upgraded\n'
  else
    printf 'Native packages: failed (exit %s)\n' "$native"
    [ "$status" != 0 ] || status=1
  fi
  return "$status"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
