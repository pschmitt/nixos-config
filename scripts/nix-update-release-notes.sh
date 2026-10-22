#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--pr-body] PACKAGE OLD_VERSION NEW_VERSION
EOF
}

get_release_notes() {
  local package="$1"
  local old_version="$2"
  local new_version="$3"
  local pr_body="${4:-}"
  local homepage
  local repo=
  local tag
  local release_json
  local compare_url=
  local formatter
  local -a args

  formatter="$(dirname "${BASH_SOURCE[0]}")/nix-update-release-notes.py"
  args=(--old-version "$old_version" --new-version "$new_version")
  if [[ -n "$pr_body" ]]
  then
    args+=(--package "$package")
  fi
  homepage="$(nix eval --raw --impure ".#packages.x86_64-linux.${package}.meta.homepage" 2>/dev/null || true)"

  if [[ "$homepage" =~ ^https?://github\.com/([^/]+)/([^/#?]+) ]]
  then
    repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    repo="${repo%.git}"
    args+=(--repo "$repo")
    for tag in "v${new_version}" "$new_version"
    do
      if release_json="$(gh api "repos/${repo}/releases/tags/${tag}" 2>/dev/null)"
      then
        printf '%s' "$release_json" | python3 "$formatter" "${args[@]}" --tag "$tag" --release-json --expand-linked-changelog
        return
      fi
    done

    if [[ -n "$old_version" && -n "$new_version" ]]
    then
      for tag in "v${old_version}...v${new_version}" "${old_version}...${new_version}"
      do
        if gh api "repos/${repo}/compare/${tag}" >/dev/null 2>&1
        then
          compare_url="https://github.com/${repo}/compare/${tag}"
          break
        fi
      done
    fi
  fi

  python3 "$formatter" "${args[@]}" --compare-url "$compare_url"
}

main() {
  local pr_body=
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]
  then
    usage
    return 0
  fi
  if [[ "${1:-}" == "--pr-body" ]]
  then
    pr_body=1
    shift
  fi
  if [[ $# -ne 3 ]]
  then
    usage >&2
    return 2
  fi
  get_release_notes "$1" "$2" "$3" "$pr_body"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
