#!/usr/bin/env bash
# End-to-end update transitions: the real start-system-control.sh hands the
# real nixpp its preload (TERMUX_PKG_REDIRECT_SO) while app versions come and
# go; nixpp's own decision (__apk-replaced) must restart a process at most
# once per update and then settle.
#
# Usage: test-start-transitions.sh NIXPP START_SCRIPT

set -euo pipefail

NIXPP=${1:?nixpp executable}
START_SCRIPT=${2:?start-system-control.sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILURES=0

# Android paths the script uses, on a fake root.
SYSTEM_BIN=$WORK/system/bin
DATA=$WORK/data/data/dev.pschmitt.termux
ALIAS=$WORK/data/user/0/dev.pschmitt.termux
RUNTIME=$DATA/files/home/.local/share/termuxpp-nix
STABLE=$DATA/files/lib/libtermux-pkg-redirect.so

setup() {
  mkdir -p "$SYSTEM_BIN" "$RUNTIME/root/tmp" "$DATA/files/usr/bin" \
    "$DATA/files/usr/lib" "$DATA/files/usr/tmp" "${ALIAS%/*}"
  ln -s "$DATA" "$ALIAS"
  ln -s "$(command -v bash)" "$SYSTEM_BIN/sh"
  ln -s "$(command -v readlink)" "$SYSTEM_BIN/readlink"
  cat >"$SYSTEM_BIN/pm" <<EOF
#!$(command -v bash)
printf 'package:%s/base.apk\n' "\$(cat "$WORK/installed-apk")"
EOF
  chmod +x "$SYSTEM_BIN/pm"
  # The real script, with /system/bin on the fake root.
  sed "s|/system/bin/|$SYSTEM_BIN/|g" "$START_SCRIPT" >"$RUNTIME/start-system-control.sh"
  # What serve would decide, instead of serving.
  cat >"$RUNTIME/nixpp" <<EOF
#!$(command -v bash)
exec "$NIXPP" --runtime "$RUNTIME" __apk-replaced
EOF
  chmod +x "$RUNTIME/nixpp"
  printf 'TERMUX_APP__DATA_DIR=%s\n' "$DATA" >"$RUNTIME/session.env"
}

# install_app DIR [stable]: an app version whose APK lives in DIR (the
# previous one is removed, as Android does). With "stable" it is a current
# app: it keeps the stable copy and records it when the script preloads it;
# otherwise it predates the copy and records its APK path.
install_app() {
  local dir=$WORK/app/$1 previous=''
  [[ -r $WORK/installed-apk ]] && previous=$(cat "$WORK/installed-apk")
  mkdir -p "$dir/lib/arm64"
  : >"$dir/lib/arm64/libtermux-pkg-redirect.so"
  printf '%s\n' "$dir" >"$WORK/installed-apk"
  [[ -n $previous && $previous != "$dir" ]] && rm -rf "$previous"
  if [[ ${2:-} == stable ]]
  then
    mkdir -p "${STABLE%/*}"
    printf '%s' "$1" >"$STABLE"
    if grep -q 'files/lib/libtermux-pkg-redirect.so' "$RUNTIME/start-system-control.sh"
    then
      printf '%s\n' "$STABLE" >"$RUNTIME/apk-library"
      return
    fi
  fi
  printf '%s\n' "$dir/lib/arm64/libtermux-pkg-redirect.so" >"$RUNTIME/apk-library"
}

# Start through the script, as the app and nixpp's restart do; prints
# "replaced" or "current". DATA_DIR overrides the spelling of the data dir.
start() {
  local data_dir=${1:-$DATA}
  printf 'TERMUX_APP__DATA_DIR=%s\n' "$data_dir" >"$RUNTIME/session.env"
  env -i PATH="$PATH" "$SYSTEM_BIN/sh" "$RUNTIME/start-system-control.sh" 2>/dev/null || true
}

# Decision for a process that is still running with PRELOAD loaded.
running_with() {
  env -i PATH="$PATH" TERMUX_PKG_REDIRECT_SO="$1" \
    "$NIXPP" --runtime "$RUNTIME" __apk-replaced 2>/dev/null || true
}

check() {
  local what=$1 expected=$2 actual=$3
  if [[ $actual == "$expected" ]]
  then
    printf 'ok   %s\n' "$what"
  else
    printf 'FAIL %s: expected %s, got %s\n' "$what" "$expected" "$actual"
    FAILURES=$((FAILURES + 1))
  fi
}

main() {
  setup

  install_app v1
  check "old app: a fresh start settles" current "$(start)"

  # Update to a current app: the process started under v1 restarts once,
  # then the restarted process settles, also under the /data/user/0 spelling.
  install_app v2 stable
  check "update: a process of the removed APK restarts" replaced \
    "$(running_with "$WORK/app/v1/lib/arm64/libtermux-pkg-redirect.so")"
  check "update: the restarted process settles" current "$(start)"
  check "update: /data/user/0 spelling settles" current "$(start "$ALIAS")"

  install_app v3 stable
  check "update between current apps: the stable copy keeps running" current \
    "$(running_with "$STABLE")"

  # Downgrade to an app that predates the stable copy. Its marker names its
  # APK library while the stable copy is still on disk.
  install_app v4
  check "downgrade: the running process restarts" replaced \
    "$(running_with "$STABLE")"
  check "downgrade: the restarted process settles" current "$(start)"

  # Back to a current app.
  install_app v5 stable
  check "upgrade after downgrade: the restarted process settles" current "$(start)"

  if ((FAILURES > 0))
  then
    printf '%d transition check(s) failed\n' "$FAILURES"
    return 1
  fi
  printf 'all transition checks passed\n'
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
