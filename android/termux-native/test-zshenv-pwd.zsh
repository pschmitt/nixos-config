#!/usr/bin/env zsh

# Termux's zsh seeds its initial $PWD from a compiled-in stock home. In a
# forked app that spelling must be normalized to the fork's home, and nothing
# else about the starting directory may change.

setopt errexit nounset pipefail

script_dir=${0:A:h}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/termux-native-zshenv-pwd.XXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

stock="$temporary/stock"
fork="$temporary/fork"
home="$fork/files/home"
generation=1111111111111111111111111111111111111111111111111111111111111111
mkdir -p "$home/sub" "$home/.local/share/termux-native/generations/$generation/home/.config/zsh" \
  "$fork/files/usr" "$stock/files"
ln -s "generations/$generation" "$home/.local/share/termux-native/current"
# The prefix redirect makes the stock spelling reach the fork's directory.
ln -s "$home" "$stock/files/home"

# usage: run START_DIR PWD_ENV [APP_DATA_DIR]; prints "PWD|OLDPWD|PHYSICAL"
run() {
  local start=$1 pwd_env=$2 data_dir=${3:-}
  local -a data=()
  [[ -n "$data_dir" ]] && data=(TERMUX_APP__DATA_DIR="$data_dir")
  (
    cd -- "$start"
    env -i PATH="$PATH" HOME="$home" PREFIX="$fork/files/usr" \
      TERMUX_NATIVE_STOCK_DATA_DIR="$stock" PWD="$pwd_env" OLDPWD="$pwd_env" \
      "${data[@]}" \
      zsh -f -c 'source "$1" || exit 1; print -r -- "$PWD|$OLDPWD|$(pwd -P)"' _ "$script_dir/zshenv"
  )
}

check() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" != "$expected" ]]
  then
    print -u2 -r -- "FAIL: $name"
    print -u2 -r -- "  expected: $expected"
    print -u2 -r -- "  actual:   $actual"
    return 1
  fi
  print -r -- "ok: $name"
}

physical=${home:A}

# Fresh session in the fork's home: stock spelling becomes the fork's home.
check "stock-spelled home is respelled for the fork" \
  "$home|$home|$physical" "$(run "$home" "$stock/files/home" "$fork")"

# An explicitly chosen directory is preserved, whatever its spelling.
check "fork-spelled home is preserved" \
  "$home|$home|$physical" "$(run "$home" "$home" "$fork")"
check "inherited fork subdirectory is preserved" \
  "$home/sub|$home/sub|$physical/sub" "$(run "$home/sub" "$home/sub" "$fork")"
check "inherited stock-spelled subdirectory is preserved" \
  "$stock/files/home/sub|$stock/files/home/sub|$physical/sub" \
  "$(run "$home/sub" "$stock/files/home/sub" "$fork")"
check "stock home is not forced onto another directory" \
  "$home/sub|$home/sub|$physical/sub" "$(run "$home/sub" "$stock/files/home" "$fork")"

# Stock Termux and shells without a redirect keep their behaviour.
check "stock app data directory is untouched" \
  "$stock/files/home|$stock/files/home|$physical" \
  "$(run "$home" "$stock/files/home" "$stock")"
check "unset app data directory is untouched" \
  "$stock/files/home|$stock/files/home|$physical" "$(run "$home" "$stock/files/home")"

print 'PASS: the stock home spelling is normalized only for the forked app'

# vim: set ft=zsh et ts=2 sw=2 :
