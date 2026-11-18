#!/system/bin/sh

main() {
  if [[ $# != 0 ]]
  then
    printf 'Usage: %s\nRun the native guest-system controller in the foreground.\n' "$0"
    case $1 in
      -h|--help) return 0 ;;
      *) return 2 ;;
    esac
  fi
  script=$(/system/bin/readlink -f "$0") || return 1
  directory=${script%/*}
  if [[ ! -r "$directory/session.env" ]]
  then
    printf 'Runtime is not prepared.\n' >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$directory/session.env"
  socket_directory=${SESSION_TMP_DIR:-$directory/root/tmp}
  data_dir=${TERMUX_APP__DATA_DIR:-/data/data/dev.pschmitt.termux}
  prefix=$data_dir/files/usr
  apk=$(/system/bin/pm path "${data_dir##*/}") || return 1
  apk=${apk#package:}
  case $apk in
    *'
'*|'')
      printf 'Cannot resolve a unique installed core APK.\n' >&2
      return 1
      ;;
  esac
  redirect=${apk%/*}/lib/arm64/libtermux-pkg-redirect.so
  if [[ ! -r $redirect || ! -x $directory/nixpp ]]
  then
    printf 'The native core redirect library and runtime nixpp binary are required.\n' >&2
    return 1
  fi
  export HOME=$data_dir/files/home PREFIX=$prefix TERMUX_APP__DATA_DIR=$data_dir
  export PATH=$prefix/bin:/system/bin TMPDIR=$prefix/tmp
  export LD_LIBRARY_PATH=$prefix/lib LD_PRELOAD=$redirect
  if [[ -r $prefix/lib/libtermux-exec.so ]]
  then
    export LD_PRELOAD=$LD_PRELOAD:$prefix/lib/libtermux-exec.so
  fi
  umask 077
  exec "$directory/nixpp" --runtime "$directory" serve \
    --socket "$socket_directory/nixpp.sock"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
