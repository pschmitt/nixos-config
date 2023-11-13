#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--outdir DIR] ARCHIVE [ARCHIVE...]"
}

extract_archive() {
  local archive="$1"
  unzip "$archive" '*.ttf' '*.otf' -d "$SRCROOT"
}

extract_archives() {
  local archives=("$@")

  for a in "${archives[@]}"
  do
    echo "Extracting fonts from ${a}..." >&2
    extract_archive "$a"
  done
}

age_encrypt_for_github_user () {
  local gh_user=pschmitt
  local keys

  if ! keys=$(curl -fsSL https://github.com/${gh_user}.keys)
  then
    echo "Failed to fetch SSH keys for user ${gh_user} from GitHub" >&2
    return 1
  fi

  age -R - $@ <<< "$keys"
}

encrypt_fonts() {
  local outdir="${1:-$OUTDIR}"

  rm -f fonts.zip fonts.zip.age

  zip -r -j fonts.zip "${outdir}"/*
  age_encrypt_for_github_user -o fonts.zip.age fonts.zip
}

find_fontdirs() {
  local dir="${1:-$PWD}"

  find "$dir" -type f \( -iname "*.ttf" -o -iname "*.otf" \) \
    -exec dirname {} \; | sort -u | grep -v "$OUTDIR"
}

patch_fonts() {
  local srcdirs=("$@")
  local extra_args=(--complete)
  local dir

  for dir in "${srcdirs[@]}"
  do
    echo "Patching fonts in ${dir}..." >&2

    docker run --pull always --rm \
      --name nerd-fonts-patcher \
      -v "${dir}:/in:ro" \
      -v "${OUTDIR}:/out:Z" \
      nerdfonts/patcher \
      "${extra_args[@]}"
  done
}

kill_container() {
  docker rm -f nerd-fonts-patcher
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  ARGS=()
  while [[ -n "$*" ]]
  do
    case "$1" in
      --help|-h|-?)
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

  if [[ -n "$EXIT" ]]
  then
    kill_container
  fi

  OUTDIR="${OUTDIR:-$PWD}/out"

  if [[ -n "$CLEAR_OUTDIR" ]]
  then
    sudo rm -rf "$OUTDIR"
  fi

  FONT_ARCHIVES=("$@")
  SRCROOT="$(mktemp -d)"
  trap 'rm -rf "$SRCROOT"' EXIT

  extract_archives "${FONT_ARCHIVES[@]}"

  mapfile -t SRCDIRS < <(find_fontdirs "$SRCROOT")

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
