#!/usr/bin/env bash

main() {
  local threshold="${1:-86400}"
  local snapshots times latest now timestamp newest=0

  if [[ ! "$threshold" =~ ^[0-9]+$ ]]
  then
    printf 'Invalid backup age threshold: %s\n' "$threshold" >&2
    return 2
  fi
  if ! snapshots="$(restic-main snapshots --json)"
  then
    printf 'Failed to query restic snapshots\n' >&2
    return 1
  fi
  if ! times="$(jq -er 'if type == "array" then [.[] | .time | select(type == "string" and length > 0)] | if length > 0 then .[] else empty end else empty end' <<< "$snapshots")"
  then
    printf 'No valid restic snapshot timestamp found\n' >&2
    return 1
  fi
  while IFS= read -r latest
  do
    if ! timestamp="$(date -d "$latest" +%s)"
    then
      printf 'Invalid restic snapshot timestamp: %s\n' "$latest" >&2
      return 1
    fi
    if (( timestamp > newest ))
    then
      newest="$timestamp"
    fi
  done <<< "$times"
  now="$(date +%s)"
  if (( now - newest > threshold ))
  then
    printf 'Last backup is older than %s seconds: %s\n' "$threshold" "$(date -d "@$newest" -Iseconds)" >&2
    return 1
  fi
  printf 'Last backup is within %s seconds: %s\n' "$threshold" "$(date -d "@$newest" -Iseconds)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
