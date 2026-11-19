#!/system/bin/sh

main() {
  unset LD_PRELOAD LD_LIBRARY_PATH
  if [[ $# != 0 && ${1:-} != --services ]]
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
  base_apk=
  while IFS= read -r line
  do
    case $line in
      package:*/base.apk) base_apk=${line#package:} ;;
    esac
  done <<EOF_APK
$apk
EOF_APK
  if [[ -z $base_apk ]]
  then
    printf 'Cannot locate the installed base APK.\n' >&2
    return 1
  fi
  redirect=${base_apk%/*}/lib/arm64/libtermux-pkg-redirect.so
  # The app keeps a stable copy that survives APK updates; the APK path is
  # only a fallback for an app that predates it.
  if [[ -r $data_dir/files/lib/libtermux-pkg-redirect.so ]]
  then
    redirect=$data_dir/files/lib/libtermux-pkg-redirect.so
  fi
  if [[ ! -r $redirect || ! -x $directory/nixpp ]]
  then
    printf 'The native core redirect library and runtime nixpp binary are required.\n' >&2
    return 1
  fi
  export HOME=$data_dir/files/home PREFIX=$prefix TERMUX_APP__DATA_DIR=$data_dir
  export PATH=$prefix/bin:/system/bin TMPDIR=$prefix/tmp
  # nixpp restarts a process whose preload differs from the apk-library marker.
  # The app and this script may spell the same file differently (/data/data
  # versus /data/user/0), so adopt the marker's spelling for the same file.
  TERMUX_PKG_REDIRECT_SO=$(/system/bin/readlink -f "$redirect") || return 1
  if [[ -r $directory/apk-library ]] && IFS= read -r recorded < "$directory/apk-library" &&
    [[ -n $recorded && $recorded -ef $redirect ]]
  then
    TERMUX_PKG_REDIRECT_SO=$recorded
  fi
  export TERMUX_PKG_REDIRECT_SO
  export LD_LIBRARY_PATH=$prefix/lib LD_PRELOAD=$redirect
  if [[ -r $prefix/lib/libtermux-exec.so ]]
  then
    export LD_PRELOAD=$LD_PRELOAD:$prefix/lib/libtermux-exec.so
  fi
  umask 077
  if [[ ${1:-} == --services ]]
  then
    exec "$directory/nixpp" --runtime "$directory" __service-supervisor
  fi
  exec "$directory/nixpp" --runtime "$directory" serve \
    --socket "$socket_directory/nixpp.sock"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
