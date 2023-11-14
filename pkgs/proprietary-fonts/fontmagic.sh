#!/usr/bin/env bash

usage() {
  echo "Usage: $0 ACTION [ARGS]"
  echo
  echo "Actions:"
  echo "   patch ARCHIVE [ARCHIVE...]"
  echo "   archive [OUTDIR]"
  echo "   encrypt [OUTDIR]"
  echo "   decrypt FILE"
  echo "   fetch"
}

echo_info() {
  echo -e "\033[1;34m$*\033[0m" >&2
}

echo_error() {
  echo -e "\033[1;31m$*\033[0m" >&2
}

extract_archive() {
  local archive="$1"
  unzip -j "$archive" '*.ttf' '*.otf' -d "$SRCROOT"
}

extract_archives() {
  local archives=("$@")

  local a
  for a in "${archives[@]}"
  do
    echo_info "📤 Extracting fonts from '${a}' to '$SRCROOT'..."
    extract_archive "$a"
  done

  echo_info "Files in $SRCROOT:"
  ls -1 "$SRCROOT"
}

age_encrypt_for_github_user () {
  local gh_user="${GITHUB_USER:-pschmitt}"
  local keys

  if ! keys=$(curl -fsSL "https://github.com/${gh_user}.keys")
  then
    echo_error "Failed to fetch SSH keys for GitHub user ${gh_user}"
    return 1
  fi

  age -R - "$@" <<< "$keys"
}

archive_fonts() {
  local outdir="${1:-${OUTDIR:-${PWD}/out}}"
  local zip_file="${outdir}/fonts.zip"

  {
    rm -f "$zip_file"

    echo_info "📦 Creating ZIP achive ${zip_file}"
    zip -r -j "$zip_file" "${outdir}"/*
  } >&2

  echo "$zip_file"
}

encrypt_fonts() {
  local outdir="${1:-${OUTDIR:-${PWD}/out}}"
  local zip_file="$(archive_fonts "$outdir")"
  local age_file="${zip_file}.age"

  rm -f "$age_file"

  echo_info "🔑 Encrypting archive to ${age_file}"
  age_encrypt_for_github_user -o "$age_file" "$zip_file"
}

decrypt_fonts() {
  local source="${1:-fonts.zip.age}"
  local dest="${DEST:-fonts.zip}"
  local age_key="${AGE_KEY:-${HOME}/.ssh/id_ed25519}"

  rm -f "$dest"

  if age --decrypt --identity "$age_key" "$source" > "$dest"
  then
    echo_info "📖 Decrypted $source to $dest"
    return 0
  fi

  echo_error "😵 Failed to decrypt $source"
  return 1
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
  local extra_args=(--complete --makegroups 2)
  local dir rc=0

  for dir in "${srcdirs[@]}"
  do
    echo_info "🔧 Patching fonts in '${dir}'..."

    docker run --pull always --rm \
      -v "${dir}:/in:Z" \
      -v "${outdir}:/out:Z" \
      nerdfonts/patcher \
      "${extra_args[@]}"

    if [[ "$?" -ne 0 ]]
    then
      echo_error "🔴 Failed to patch fonts in '${dir}'"
      rc=1
    fi
  done

  return "$rc"
}

copy_original_fonts() {
  local srcdirs=("$@")
  local outdir="${OUTDIR:-${PWD}/out}"

  echo_info "📋 Copying original fonts to $outdir"
  find "${srcdirs[@]}" \( -iname "*.ttf" -o -iname "*.otf" \) \
    -exec cp -v --no-clobber {} "$outdir" \;
}

kill_container() {
  echo_info "💀 Killing nerdfonts containers..."

  docker ps | awk '/nerdfonts/ { print $1 }' | \
    xargs --no-run-if-empty docker rm -f
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  ARGS=()
  ACTION=patch

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

  ACTION="$1"

  if [[ -z "$ACTION" ]]
  then
    {
      echo "Missing action"
      usage
      exit 2
    }>&2
  fi
  shift

  OUTDIR="${OUTDIR:-$PWD}/out"
  FONT_ARCHIVES=("$@")

  RC=0

  case "$ACTION" in
    exit|stop|kill)
      kill_container
      RC="$?"
      ;;
    patch)
      if [[ -n "$EXIT" ]]
      then
        kill_container
      fi

      if [[ -n "$CLEAR_OUTDIR" ]]
      then
        echo "Clearing OUTDIR ${OUTDIR}..." >&2
        sudo rm -vrf "$OUTDIR"
      fi

      mkdir -p "$OUTDIR"
      SRCROOT="$(mktemp -d)"
      trap 'rm -rf "$SRCROOT"' EXIT

      extract_archives "${FONT_ARCHIVES[@]}"

      # FIXME this might be irrelevant since we extract all fonts to SRCROOT (w/o dirs)
      mapfile -t SRCDIRS < <(find_fontdirs "$SRCROOT")

      copy_original_fonts "${SRCDIRS[@]}"
      patch_fonts "${SRCDIRS[@]}"
      RC="$?"

      if [[ "$RC" -eq 0 ]]
      then
        sudo chown -R "$USER" "$OUTDIR"
      else
        echo_error "🔴 Patching failed"
        sudo rmdir "$OUTDIR" 2>/dev/null
        exit "$RC"
      fi

      if [[ -n "$ENCRYPT" ]]
      then
        encrypt_fonts "$OUTDIR"
      fi
      ;;
    encrypt)
      encrypt_fonts "$OUTDIR"
      RC="$?"
      ;;
    decrypt)
      decrypt_fonts $@
      RC="$?"
      ;;
    archive)
      archive_fonts "$OUTDIR"
      RC="$?"
      ;;
    *)
      echo_error "Unknown action: ${ACTION}"
      RC=2
      ;;
  esac

  exit "$RC"
fi

# vim: set ft=bash et ts=2 sw=2 :
