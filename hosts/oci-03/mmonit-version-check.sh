#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Checks whether the packaged M/Monit version is behind the latest upstream
release advertised by mmonit.com.
EOF
}

mmonit_version() {
  printf '%s\n' "${MMONIT_PACKAGE_VERSION:-}"
}

mmonit_latest_version() {
  curl -fsSL https://mmonit.com/releases.json |
    jq -er '.mmonit.version // empty'
}

version_lt() {
  [[ "$(printf "%s\n%s" "$@" | sort -V | tail -n 1)" != "$1" ]]
}

main() {
  local mmonit_version
  local latest_mmonit_version

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]
  then
    usage
    return 0
  fi

  if [[ -n "${1:-}" ]]
  then
    usage >&2
    echo "Unknown argument: $1" >&2
    return 2
  fi

  mmonit_version="$(mmonit_version)"

  if [[ -z "$mmonit_version" ]]
  then
    echo "Failed to determine the packaged version of mmonit" >&2
    return 1
  fi

  if ! latest_mmonit_version="$(mmonit_latest_version)"
  then
    echo "Failed to determine the latest version of mmonit" >&2
    return 1
  fi

  if [[ -z "$latest_mmonit_version" ]]
  then
    echo "Failed to determine the latest version of mmonit" >&2
    return 1
  fi

  if [[ "$mmonit_version" == "$latest_mmonit_version" ]]
  then
    echo "mmonit is up to date ($mmonit_version)"
    return 0
  elif ! version_lt "$mmonit_version" "$latest_mmonit_version"
  then
    echo "mmonit is running a *newer* version"
    echo "Currently packaged: $mmonit_version"
    echo "Latest release: $latest_mmonit_version"
    return 0
  else
    {
      echo "A new version of mmonit is available: $latest_mmonit_version"
      echo "Currently packaged: $mmonit_version"
    } >&2

    # Exiting with 1 here will make the check red
    # exit 1
    return 0
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=bash ts=2 sw=2 sts=2 et:
