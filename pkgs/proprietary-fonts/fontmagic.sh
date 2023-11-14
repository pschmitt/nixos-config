#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--outdir DIR] [--encrypt] [--stop] [--clear] ARCHIVE [ARCHIVE...]"
}

extract_archive() {
  local archive="$1"
  unzip "$archive" '*.ttf' '*.otf' -d "$SRCROOT"
}

extract_archives() {
  local archives=("$@")

  local a
  for a in "${archives[@]}"
  do
    echo "Extracting fonts from ${a}..." >&2
    extract_archive "$a"
  done
}

age_encrypt_for_github_user () {
  local gh_user=pschmitt
  local keys

  if ! keys=$(curl -fsSL "https://github.com/${gh_user}.keys")
  then
    echo "Failed to fetch SSH keys for GitHub user ${gh_user}" >&2
    return 1
  fi

  age -R - "$@" <<< "$keys"
}

encrypt_fonts() {
  local outdir="${1:-${OUTDIR:-${PWD}/out}}"
  local zip_file="${outdir}/fonts.zip"
  local age_file="${zip_file}.age"

  rm -f "$zip_file" "$age_file"

  echo "🗄️ Creating ZIP achive ${zip_file}" >&2
  zip -r -j "$zip_file" "${outdir}"/*

  echo "🔑 Encrypting archive to ${age_file}" >&2
  age_encrypt_for_github_user -o "$age_file" "$zip_file"
}

find_fontdirs() {
  local dir="${1:-$PWD}"
  local outdir="${OUTDIR:-${PWD}/out}"

  find "$dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) \
    -exec dirname {} \; | sort -u | grep -v -- "$outdir"
}

patch_fonts() {
  local srcdirs=("$@")
  local outdir="${OUTDIR:-${PWD}/out}"
  local extra_args=(--complete --adjust-line-height)
  local dir rc=0

  for dir in "${srcdirs[@]}"
  do
    echo "Patching fonts in '${dir}'..." >&2

    docker run --pull always --rm \
      -v "${dir}:/in:Z" \
      -v "${outdir}:/out:Z" \
      nerdfonts/patcher \
      "${extra_args[@]}" &

    [[ "$?" -ne 0 ]] && rc=1
  done

  wait
  return "$rc"
}

copy_original_fonts() {
  local srcdirs=("$@")
  local outdir="${OUTDIR:-${PWD}/out}"

  find "${srcdirs[@]}" \( -iname "*.ttf" -o -iname "*.otf" \) \
    -exec cp -v --no-clobber {} "$outdir" \;
}

kill_container() {
  docker ps | awk '/nerdfonts/ { print $1 }' | xargs docker rm -f
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  ARGS=()

  while [[ -n "$*" ]]
  do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --outdir|--output|-o)
        OUTDIR="$2"
        shift 2
        ;;
      --clear|-c|--force|-f)
        CLEAR_OUTDIR=1
        shift
        ;;
      --encrypt|-e)
        ENCRYPT=1
        shift
        ;;
      --stop|--exit)
        EXIT=1
        shift
        ;;
      *)
        ARGS+=("$1")
        shift
        ;;
    esac
  done

  set -- "${ARGS[@]}"

  OUTDIR="${OUTDIR:-$PWD}/out"
  FONT_ARCHIVES=("$@")

  if [[ -n "$EXIT" ]]
  then
    kill_container
  fi

  if [[ -n "$CLEAR_OUTDIR" ]]
  then
    sudo rm -rf "$OUTDIR"
  fi

  SRCROOT="$(mktemp -d)"
  trap 'rm -rf "$SRCROOT"' EXIT

  extract_archives "${FONT_ARCHIVES[@]}"

  mapfile -t SRCDIRS < <(find_fontdirs "$SRCROOT")

  copy_original_fonts "${SRCDIRS[@]}"
  patch_fonts "${SRCDIRS[@]}"
  RC="$?"

  if [[ "$RC" -eq 0 ]]
  then
    sudo chown -R "$USER" "$OUTDIR"
  else
    sudo rmdir "$OUTDIR" 2>/dev/null
    exit "$RC"
  fi

  if [[ -n "$ENCRYPT" ]]
  then
    encrypt_fonts "$OUTDIR"
  fi

  exit "$RC"
fi

# vim: set ft=bash et ts=2 sw=2 :
