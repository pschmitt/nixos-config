#!/system/bin/sh

# shellcheck source-path=SCRIPTDIR
usage() {
  printf 'Usage: %s [--bootstrap | --legacy | --system CANDIDATE] [-- COMMAND ARG...]\n' "$0"
}

main() {
  script=$(/system/bin/readlink -f "$0") || return 1
  directory=${script%/*}
  if [[ ! -r "$directory/session.env" ]]
  then
    printf 'Runtime is not prepared: %s\n' "$directory" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$directory/session.env"
  session_user=${SESSION_USER:-nix}
  session_home=${SESSION_HOME:-/home/$session_user}
  if [[ $(/system/bin/uname -m) != aarch64 || $(/system/bin/getconf PAGE_SIZE) != 4096 ]]
  then
    printf 'This experimental runtime requires AArch64 with 4096-byte pages.\n' >&2
    return 1
  fi
  bootstrap=
  legacy=
  system_candidate=
  session_etc="$directory/root/etc"
  case ${1:-} in
    -h|--help)
      usage
      return 0
      ;;
    --bootstrap)
      bootstrap=1
      shift
      ;;
    --legacy)
      legacy=1
      shift
      ;;
    --system)
      if [[ $# -lt 2 ]]
      then
        usage >&2
        return 2
      fi
      system_candidate=$2
      # shellcheck source=system-session.sh
      . "$directory/system-session.sh" || return 1
      load_system_candidate "$directory" "$system_candidate" || return 1
      shift 2
      ;;
  esac
  if [[ -z $bootstrap && -z $legacy && -z $system_candidate && ( -e "$directory/current-system" || -L "$directory/current-system" ) ]]
  then
    if [[ -L "$directory/current-system" || ! -f "$directory/current-system" ]]
    then
      printf 'Invalid default system selection. Use --legacy or --bootstrap for recovery.\n' >&2
      return 1
    fi
    if ! {
      IFS= read -r system_candidate &&
      {
        ! IFS= read -r selection_extra && [[ -z $selection_extra ]]
      }
    } < "$directory/current-system"
    then
      printf 'Invalid default system selection. Use --legacy or --bootstrap for recovery.\n' >&2
      return 1
    fi
    if [[ -n $system_candidate ]]
    then
      # shellcheck source=system-session.sh
      . "$directory/system-session.sh" || return 1
      load_system_candidate "$directory" "$system_candidate" || return 1
    fi
  fi
  if [[ ${1:-} == -- ]]
  then
    shift
  fi
  if [[ -n $bootstrap ]]
  then
    command_path="$BOOTSTRAP_NIX/bin:$BOOTSTRAP_BUSYBOX/bin:/bin"
    login_shell=/bin/sh
    certificate="/android$ANDROID_CA"
  else
    command_path="$session_home/.nix-profile/bin:$SESSION_PATH"
    login_shell=$SESSION_SHELL
    certificate=$SESSION_CERTIFICATE
    if [[ ! -x "$directory/root$login_shell" ]]
    then
      printf 'Session packages are not installed; finish bootstrap first.\n' >&2
      return 1
    fi
    if [[ -n $system_candidate ]]
    then
      command_path="$session_home/.nix-profile/bin:/run/current-system/sw/bin"
    fi
  fi
  if [[ $# -gt 0 ]]
  then
    target=/bin/sh
    set -- -c 'exec "$@"' sh "$@"
  elif [[ -n $bootstrap ]]
  then
    target=/bin/sh
    set -- -i
  else
    target=$login_shell
    set -- --noprofile --rcfile /etc/bashrc -i
  fi
  runtime_uid=$(/system/bin/id -u) || return 1
  (umask 077; /system/bin/mkdir -p "$directory/root/run/user/$runtime_uid") || return 1
  runtime_dir=
  if [[ -f "$session_etc/termuxpp-release" ]] &&
    /system/bin/grep -qx 'XDG_RUNTIME_DIR_LAYOUT=run-user' "$session_etc/termuxpp-release"
  then
    runtime_dir="/run/user/$runtime_uid"
  fi
  set -- "$target" "$target" "$@"
  if [[ -n $system_candidate ]]
  then
    set -- -b "$directory/root/nix/store/$system_candidate:/run/current-system!" "$@"
  fi
  cd "$directory/root$session_home" || return 1
  exec /system/bin/env -i \
    HOME="$session_home" USER="$session_user" LOGNAME="$session_user" \
    TERM="${TERM:-xterm-256color}" COLORTERM="${COLORTERM:-truecolor}" \
    LANG=C.UTF-8 TMPDIR=/tmp SHELL="$login_shell" \
    NIXPP_RUNTIME="/android$directory" NIXPP_SOCKET=/tmp/nixpp.sock \
    NIXPP_OUTER_SOCKET="${NIXPP_OUTER_SOCKET:-}" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    NIX_CONF_DIR="$session_home/.config/nix" \
    PATH="$command_path" TERMINFO="$SESSION_TERMINFO" \
    NIX_SSL_CERT_FILE="$certificate" SSL_CERT_FILE="$certificate" \
    NIX_CONFIG='sandbox = false
build-users-group =
experimental-features = nix-command flakes
substituters = https://cache.nixos.org
require-sigs = true
auto-optimise-store = false' \
    "$directory/launcher" \
    -b "$directory/root/nix:/nix" \
    -b "$session_etc:/etc!" \
    -b "$directory/root/bin:/bin!" \
    -b "$directory/root/home:/home" \
    -b "${SESSION_TMP_DIR:-$directory/root/tmp}:/tmp" \
    -b "$directory/root/run:/run!" \
    -b "$directory:/run/nixpp-runtime!" \
    -b "$directory/root/usr:/usr" \
    -b "$directory/root/dev/shm:/dev/shm" \
    -b "$directory/proc-stat:/proc/stat" \
    -b "$directory/proc-uptime:/proc/uptime" \
    -b /:/android \
    "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
