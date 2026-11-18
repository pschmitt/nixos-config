#!/system/bin/sh

usage() {
  printf 'Usage: %s [--socket-dir NATIVE_DIRECTORY]\n' "$0"
  printf 'Run the allowlisted Android bridge in the foreground, outside the Linux guest.\n'
}

main() {
  socket_dir=
  case ${1:-} in
    -h|--help)
      usage
      return 0
      ;;
    --socket-dir)
      if [[ $# != 2 || -z $2 ]]
      then
        usage >&2
        return 2
      fi
      socket_dir=$2
      ;;
    '') ;;
    *)
      usage >&2
      return 2
      ;;
  esac
  script=$(/system/bin/readlink -f "$0") || return 1
  directory=${script%/*}
  data_dir=${TERMUX_APP__DATA_DIR:-/data/data/dev.pschmitt.termux}
  prefix=$data_dir/files/usr
  native_home=$data_dir/files/home
  socket_dir=${socket_dir:-$native_home/.cache/tn/android-bridge}
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
  if [[ ! -r $redirect || ! -x $prefix/bin/python3 ]]
  then
    printf 'The native core redirect library and Python are required.\n' >&2
    return 1
  fi
  export HOME=$native_home PREFIX=$prefix TERMUX_APP__DATA_DIR=$data_dir
  export PATH=$prefix/bin:/system/bin TMPDIR=$prefix/tmp
  export LD_LIBRARY_PATH=$prefix/lib
  export LD_PRELOAD=$redirect
  if [[ -r $prefix/lib/libtermux-exec.so ]]
  then
    export LD_PRELOAD=$LD_PRELOAD:$prefix/lib/libtermux-exec.so
  fi
  exec "$prefix/bin/python3" -I "$directory/android-bridge.py" serve \
    --prefix "$prefix" --socket-dir "$socket_dir"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
