#!/usr/bin/env zsh

setopt errexit nounset pipefail

script_dir=${0:A:h}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/termux-native-zshenv.XXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT

home="$temporary/home"
root="$home/.local/share/termux-native"
prefix="$temporary/prefix"
first=1111111111111111111111111111111111111111111111111111111111111111
second=2222222222222222222222222222222222222222222222222222222222222222
legacy=3333333333333333333333333333333333333333333333333333333333333333
mkdir -p "$root/generations/$first/home/.config/zsh" \
  "$root/generations/$second/home/.config/zsh" \
  "$root/generations/$first/bin" "$root/generations/$legacy/bin" \
  "$root/generations/$legacy/shell/plugins/completions" \
  "$temporary/cache/zsh/local-plugins/build/functions.zwc" "$prefix"
ln -s "generations/$first" "$root/current"

export HOME="$home" PREFIX="$prefix" XDG_CACHE_HOME="$temporary/cache"
path=("$root/generations/$legacy/bin" "$root/generations/$first/bin" "$prefix/bin" $path)
fpath=(
  "$root/generations/$legacy/shell/plugins/completions"
  "$temporary/cache/zsh/local-plugins/build/functions.zwc"
  $fpath
)
export ZSH_LOCAL_PLUGIN_CACHE_DIR="$temporary/cache/zsh/local-plugins"
export ZSH_LOCAL_PLUGINS_CACHE_BUILD="$temporary/cache/zsh/local-plugins/build"
unset TERMUX_NATIVE_GENERATION_OVERRIDE TERMUX_NATIVE_ZDOTDIR
source "$script_dir/zshenv"
unset LD_PRELOAD

[[ "$TERMUX_GENERATION" == "$root/generations/$first" ]]
[[ "$ZDOTDIR" == "$TERMUX_GENERATION/home/.config/zsh" ]]
(( ${path[(Ie)$root/generations/$first/bin]} > 0 ))
(( ${path[(Ie)$root/generations/$legacy/bin]} == 0 ))
(( ${fpath[(Ie)$root/generations/$legacy/shell/plugins/completions]} == 0 ))
(( ${fpath[(Ie)$temporary/cache/zsh/local-plugins/build/functions.zwc]} == 0 ))
[[ -z "${ZSH_LOCAL_PLUGIN_CACHE_DIR:-}" && -z "${ZSH_LOCAL_PLUGINS_CACHE_BUILD:-}" ]]

# A live shell must keep its startup files tied to the generation it started
# with after a later activation atomically changes `current`.
ln -s "generations/$second" "$root/.next"
mv -Tf "$root/.next" "$root/current"
[[ "$TERMUX_GENERATION" == "$root/generations/$first" ]]
[[ "$ZDOTDIR" == "$root/generations/$first/home/.config/zsh" ]]

print 'PASS: TERMUX_GENERATION and ZDOTDIR remain on one immutable generation'

# vim: set ft=zsh et ts=2 sw=2 :
