# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Run timewsync, then rejoin the interval it splits if tracking was active:
timewsync stops the active interval before syncing and restarts it
afterwards, leaving two back-to-back database rows instead of one
continuous interval.
EOF
}

merge_sync_split() {
  local orig_start="$1" orig_tags="$2"

  [[ "$(timew get dom.active 2>/dev/null)" == "1" ]] || return 0

  local active active_start active_tags
  active=$(timew export @1) || return 0
  active_start=$(jq -er '.[0].start' <<< "$active") || return 0
  active_tags=$(jq -cSr '.[0].tags' <<< "$active")

  [[ "$active_tags" == "$orig_tags" ]] || return 0
  [[ "$active_start" != "$orig_start" ]] || return 0 # nothing split

  local previous prev_start prev_end
  previous=$(timew export @2) || return 0
  [[ -n "$previous" && "$previous" != "[]" ]] || return 0
  prev_start=$(jq -er '.[0].start' <<< "$previous")
  prev_end=$(jq -er '.[0].end // empty' <<< "$previous")

  [[ "$prev_start" == "$orig_start" && "$prev_end" == "$active_start" ]] || return 0

  printf 'Merging interval split left by timewsync\n'
  timew join @1 @2
}

main() {
  if [[ -n "${1:-}" ]]
  then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  local was_active=0 orig_start="" orig_tags=""
  if [[ "$(timew get dom.active 2>/dev/null)" == "1" ]]
  then
    was_active=1
    orig_start=$(timew export @1 | jq -er '.[0].start')
    orig_tags=$(timew export @1 | jq -cSr '.[0].tags')
  fi

  timewsync --data-dir "${XDG_CONFIG_HOME:-$HOME/.config}/timewsync"

  if [[ "$was_active" -eq 1 ]]
  then
    merge_sync_split "$orig_start" "$orig_tags"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
