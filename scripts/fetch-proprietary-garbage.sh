#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: fetch-proprietary-garbage.sh [DIRECTORY] [--base-url URL] [--username USER] [--password PASS] [--auth USER:PASS]

Arguments:
  DIRECTORY         Directory containing sha256sum.txt (default: current directory)

Environment variables:
  BLOBS_URL         Default download endpoint (default: https://blobs.brkn.lol/private/fonts)
  BLOBS_BASIC_AUTH  Provide HTTP basic auth credentials directly (USER:PASS)
  BLOBS_USERNAME    Username part of the credentials
  BLOBS_PASSWORD    Password part of the credentials
USAGE
}

list_files() {
  awk '{ print $2 }' ./sha256sum.txt
}

file_checksum() {
  local file="$1"
  awk -v file="$file" '$2 == file { print $1; exit 0 }' ./sha256sum.txt
}

file_url() {
  local file="$1"
  local default_url="${BLOBS_URL%/}/${file}"
  
  if [[ -f ./urls.txt ]]; then
    awk -v file="$file" -v def_url="$default_url" '$1 == file { print $2; exit 0 } END { if (NR==0 || !found) print def_url }' ./urls.txt
  else
    echo "$default_url"
  fi
}

file_is_valid() {
  local file="$1"
  local checksum="$2"

  [[ -f "$file" ]] || return 1

  if printf "%s  %s\n" "$checksum" "$file" | sha256sum --status --check -
  then
    return 0
  fi

  return 1
}

check_files() {
  sha256sum -c ./sha256sum.txt "$@"
}

fetch_files() {
  local file checksum url tmp_file
  local -a curl_args=(
    --fail
    --location
    --retry 5
    --retry-delay 2
    --silent
    --show-error
  )

  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
    echo "BLOBS_BASIC_AUTH is required to download private files" >&2
    return 1
  fi

  curl_args+=(
    --user "$BLOBS_BASIC_AUTH"
  )

  for file in $(list_files)
  do
    checksum="$(file_checksum "$file")"
    if [[ -z "$checksum" ]]
    then
      echo "No checksum found for $file" >&2
      return 1
    fi

    if file_is_valid "$file" "$checksum"
    then
      continue
    fi

    url="$(file_url "$file")"
    echo "Downloading $file from $url..."

    tmp_file="$(mktemp "${file}.XXXXXX")"
    if ! curl "${curl_args[@]}" \
      "$url" \
      --output "$tmp_file"
    then
      rm -f "$tmp_file"
      return 1
    fi

    mv "$tmp_file" "$file"
    
    echo "Adding $file to Nix store..."
    nix-store --add-fixed sha256 "$file"
  done

  check_files
}

process_directory() {
  local dir="$1"
  (
    cd "$dir" || exit 1
    if check_files --quiet --status 2>/dev/null; then
      echo -e "\e[32m✅All archives present and accounted for in $dir\e[0m"
      exit 0
    fi
    echo "Processing $dir..."
    fetch_files
  )
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  BLOBS_URL=${BLOBS_URL:-https://blobs.brkn.lol/private/fonts}
  BLOBS_USERNAME=${BLOBS_USERNAME:-}
  BLOBS_PASSWORD=${BLOBS_PASSWORD:-}
  BLOBS_AUTH=${BLOBS_AUTH:-}
  TARGET_DIR=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --base-url)
        BLOBS_URL="$2"
        shift 2
        ;;
      --username)
        BLOBS_USERNAME="$2"
        shift 2
        ;;
      --password)
        BLOBS_PASSWORD="$2"
        shift 2
        ;;
      --auth)
        BLOBS_AUTH="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
      *)
        TARGET_DIR="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$TARGET_DIR" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"
    TARGET_DIR="$SCRIPT_DIR/../pkgs"
  fi

  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
    if [[ -n "$BLOBS_AUTH" ]]
    then
      BLOBS_BASIC_AUTH="$BLOBS_AUTH"
    elif [[ -n "$BLOBS_USERNAME" || -n "$BLOBS_PASSWORD" ]]
    then
      if [[ -z "$BLOBS_USERNAME" || -z "$BLOBS_PASSWORD" ]]
      then
        echo "--username and --password must be provided together" >&2
        exit 64
      fi

      BLOBS_BASIC_AUTH="${BLOBS_USERNAME}:${BLOBS_PASSWORD}"
    fi
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Directory not found: $TARGET_DIR" >&2
    exit 1
  fi

  FOUND_FILES=0
  while IFS= read -r -d '' checksum_file; do
    FOUND_FILES=1
    dir="$(dirname "$checksum_file")"
    process_directory "$dir"
  done < <(find "$TARGET_DIR" -name sha256sum.txt -print0)

  if [[ "$FOUND_FILES" -eq 0 ]]; then
    echo "No sha256sum.txt files found in $TARGET_DIR or its subdirectories." >&2
    exit 1
  fi
fi
