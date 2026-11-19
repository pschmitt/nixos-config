#!/system/bin/sh

script=$(/system/bin/readlink -f "$0") || exit 1
directory=${script%/*}
# The native daemon (start-system-control.sh) supervises the guest services
# and the Android bridge; starting it again is harmless.
# The app owns the daemon (its watchdog starts it). A run-as shell (ADB
# recovery) runs in another SELinux context that app restarts never stop, so
# a daemon started from there would outlive every app restart.
context=$(cat /proc/self/attr/current 2>/dev/null) || context=
if [[ -f "$directory/system.enabled" && -r "$directory/start-system-control.sh" &&
  $context != *:runas_app:* ]]
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
  if [ -x "$HOME/.nix-profile/bin/zsh" ]; then
    export SHELL="$HOME/.nix-profile/bin/zsh"
    export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
    exec "$SHELL" "$@"
  fi
  # No Home Manager profile yet (a new runtime): the pinned session bash.
  SHELL=$(command -v bash) || exit 127
  export SHELL
  if [ "$#" -eq 1 ] && [ "$1" = -l ]; then
    exec "$SHELL" --noprofile --rcfile /etc/bashrc -i
  fi
  exec "$SHELL" "$@"
' sh "$@"

# vim: set ft=sh et ts=2 sw=2 :
