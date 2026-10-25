#!/usr/bin/env bash

# Add the sources of proprietary packages (`requireFile`) to the Nix store so
# CI can build them. Each source is downloaded only when its expected store
# path is missing, checked against that path and kept alive by a GC root.

usage() {
  cat <<EOF
Usage: $(basename "$0") SOURCES_JSON

SOURCES_JSON is a JSON list of {name, url, path} objects; path is the store
path \`requireFile\` expects for the file.

Environment variables:
  NIX_PROPRIETARY_NETRC  netrc file with the credentials for the source URLs
  NIX_PROPRIETARY_ROOTS  GC root directory
                         (default: /nix/var/nix/gcroots/proprietary-sources)
EOF
}

seed_source() {
  local name="$1"
  local url="$2"
  local path="$3"
  local roots="$4"
  local tmp_dir added

  if nix-store --check-validity "$path" 2>/dev/null
  then
    ln -sfn "$path" "${roots}/${name}"
    return 0
  fi

  tmp_dir="$(mktemp -d)"
  if ! curl --fail --location --silent --show-error --retry 3 \
    --netrc-file "${NIX_PROPRIETARY_NETRC:-/dev/null}" \
    --output "${tmp_dir}/${name}" "$url"
  then
    printf 'Failed to download %s\n' "$url" >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  added="$(nix-store --add-fixed sha256 "${tmp_dir}/${name}")"
  rm -rf "$tmp_dir"
  if [[ "$added" != "$path" ]]
  then
    # Wrong content (e.g. an auth error page); leave nothing behind.
    printf 'Unexpected content for %s: got %s, expected %s\n' "$name" "$added" "$path" >&2
    nix-store --delete "$added" >/dev/null 2>&1
    return 1
  fi

  ln -sfn "$path" "${roots}/${name}"
  printf 'Added %s\n' "$path"
}

release_stale_roots() {
  local roots="$1"
  local sources="$2"
  local root

  for root in "$roots"/*
  do
    [[ -L "$root" ]] || continue
    if ! jq -e --arg name "$(basename "$root")" 'any(.[]; .name == $name)' "$sources" >/dev/null
    then
      rm -f "$root"
      printf 'Released %s\n' "$(basename "$root")"
    fi
  done
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      usage >&2
      return 2
      ;;
  esac

  local sources="$1"
  local roots="${NIX_PROPRIETARY_ROOTS:-/nix/var/nix/gcroots/proprietary-sources}"
  local name url path
  local -a failed=()

  mkdir -p "$roots"
  while IFS=$'\t' read -r name url path
  do
    seed_source "$name" "$url" "$path" "$roots" || failed+=("$name")
  done < <(jq -r '.[] | [.name, .url, .path] | @tsv' "$sources")

  release_stale_roots "$roots" "$sources"

  if (( ${#failed[@]} > 0 ))
  then
    printf 'Failed: %s\n' "${failed[*]}" >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
