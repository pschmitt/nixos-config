#!/system/bin/sh

script=$(/system/bin/readlink -f "$0") || exit 1
directory=${script%/*}
if [[ -f "$directory/bridge.enabled" && -r "$directory/start-android-bridge.sh" ]]
then
  /system/bin/sh "$directory/start-android-bridge.sh" </dev/null >>"$directory/bridge.log" 2>&1 &
fi
if [[ -f "$directory/system.enabled" && -r "$directory/start-system-control.sh" ]]
then
  (
    umask 077
    exec /system/bin/sh "$directory/start-system-control.sh" </dev/null >>"$directory/system-control.log" 2>&1
  ) &
fi
if [[ $# -eq 0 ]]
then
  set -- -l
fi
# HOME is assigned by session.sh inside the guest, not by the native shell.
# shellcheck disable=SC2016
exec "$directory/session.sh" -- /bin/sh -c '
  export SHELL="$HOME/.nix-profile/bin/zsh"
  export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
  exec "$SHELL" "$@"
' sh "$@"

# vim: set ft=sh et ts=2 sw=2 :
