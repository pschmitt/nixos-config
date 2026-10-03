#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") PACKAGE OLD_VERSION NEW_VERSION
EOF
}

get_release_notes() {
  local package="$1"
  local old_version="$2"
  local new_version="$3"
  local homepage
  local owner
  local repo
  local tag
  local release_json
  local release_url
  local release_body
  local compare_from
  local compare_to

  homepage="$(nix eval --raw --impure ".#packages.x86_64-linux.${package}.meta.homepage" 2>/dev/null || true)"

  if [[ ! "$homepage" =~ ^https?://github\.com/([^/]+)/([^/#?]+) ]]
  then
    printf '### Release notes\n\nNo upstream GitHub release notes found for %s.' "$new_version"
    return 0
  fi

  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  repo="${repo%.git}"

  for tag in "v${new_version}" "$new_version"
  do
    if ! release_json="$(gh api "repos/${owner}/${repo}/releases/tags/${tag}" 2>/dev/null)"
    then
      continue
    fi

    release_url="$(jq -r '.html_url' <<<"$release_json")"
    release_body="$(jq -r '.body // ""' <<<"$release_json")"

    printf '### Release notes for %s\n\n' "$tag"
    if [[ -n "$release_body" ]]
    then
      printf '%s\n\n' "$release_body"
    else
      printf '_The upstream release has no notes._\n\n'
    fi
    printf '[Upstream release](%s)' "$release_url"
    return 0
  done

  compare_from="v${old_version}"
  compare_to="v${new_version}"

  if ! gh api "repos/${owner}/${repo}/compare/${compare_from}...${compare_to}" >/dev/null 2>&1
  then
    compare_from="$old_version"
    compare_to="$new_version"
  fi

  printf '### Release notes\n\nNo upstream release notes were published for %s. [Compare %s to %s](https://github.com/%s/%s/compare/%s...%s).' \
    "$new_version" "$old_version" "$new_version" "$owner" "$repo" "$compare_from" "$compare_to"
}

main() {
  if [[ $# -ne 3 ]]
  then
    usage >&2
    return 2
  fi

  get_release_notes "$1" "$2" "$3"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
