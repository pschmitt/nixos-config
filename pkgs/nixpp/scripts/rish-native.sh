#!/system/bin/sh

set -eu

extract_asset() {
  local asset="$1" destination="$2" temporary
  temporary=$(/system/bin/mktemp "$cache/.rish.XXXXXXXX") || return 1
  if /system/bin/unzip -p "$apk" "assets/$asset" > "$temporary" &&
    [ -s "$temporary" ] &&
    /system/bin/chmod 400 "$temporary" &&
    /system/bin/mv -f "$temporary" "$destination"
  then
    return 0
  fi
  /system/bin/rm -- "$temporary"
  printf 'rish: could not extract %s from the Shizuku APK.\n' "$asset" >&2
  return 1
}

main() {
  local apk_paths apk digest cache
  # Android's app_process must load system libraries, including liblzma.
  unset LD_LIBRARY_PATH LD_PRELOAD
  export PATH=/system/bin
  # Package Manager cannot use the app's PTY descriptors across Binder.
  if ! apk_paths=$(/system/bin/pm path moe.shizuku.privileged.api </dev/null 2>&1)
  then
    printf 'rish: Android could not look up the Shizuku APK. Is Shizuku installed in this Android profile?\n' >&2
    return 1
  fi
  apk=$(printf '%s\n' "$apk_paths" |
    /system/bin/sed -n 's@^package:\(.*\/base\.apk\)$@\1@p')
  if [ ! -r "$apk" ]
  then
    printf 'rish: Android did not expose a readable Shizuku base APK.\n' >&2
    return 1
  fi

  umask 077
  digest=$(/system/bin/sha256sum "$apk") || return 1
  cache="${PREFIX:?}/tmp/rish/${digest%% *}"
  /system/bin/mkdir -p "$cache" || return 1
  if [ ! -s "$cache/rish_shizuku.dex" ] || [ -w "$cache/rish_shizuku.dex" ]
  then
    extract_asset rish_shizuku.dex "$cache/rish_shizuku.dex" || return 1
  fi
  if [ ! -s "$cache/rish" ] || [ -w "$cache/rish" ]
  then
    extract_asset rish "$cache/rish" || return 1
  fi

  export RISH_APPLICATION_ID=dev.pschmitt.termux
  exec /system/bin/sh "$cache/rish" "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
