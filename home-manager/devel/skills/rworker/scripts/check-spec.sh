#!/usr/bin/env bash
# Check that rworker's command spec (what the completions read), its
# dispatch and its per-action help all list the same actions and flags.
# Runs as the flake check rworker-completions.
# usage: check-spec.sh RWORKER_SH

usage() {
  printf 'Usage: %s RWORKER_SH\n' "$(basename "$0")"
}

# Actions the main dispatch handles (second case block of main()).
dispatched() {
  awk '
    /^main\(\)/ { in_main = 1 }
    in_main && /^  shift$/ { after_shift = 1 }
    in_main && after_shift && /^    [a-z][a-z0-9-]*\)$/ { gsub(/[ )]/, ""); print }
    in_main && /^}$/ { exit }
  ' "$1" | sort -u
}

# Actions action_help() documents.
helped() {
  awk '
    /^action_help\(\)/ { in_help = 1 }
    in_help && /^    [a-z][a-z0-9-]*\)$/ { gsub(/[ )]/, ""); print }
    in_help && /^}$/ { exit }
  ' "$1" | sort -u
}

main() {
  local script="${1:-}" spec actions failed=""
  if [[ -z "$script" ]]
  then
    usage >&2
    return 2
  fi
  spec=$(bash "$script" __spec) || return 1
  # `help` is handled before the dispatch.
  actions=$(sed -n 's/^action \([^ ]*\) .*/\1/p' <<< "$spec" | grep -v -x help | sort -u)

  if ! diff <(printf '%s\n' "$actions") <(dispatched "$script") > /dev/null
  then
    printf 'spec actions and dispatch differ:\n' >&2
    diff <(printf '%s\n' "$actions") <(dispatched "$script") >&2
    failed=1
  fi
  if ! diff <(printf '%s\n' "$actions") <(helped "$script") > /dev/null
  then
    printf 'spec actions and action_help differ:\n' >&2
    diff <(printf '%s\n' "$actions") <(helped "$script") >&2
    failed=1
  fi

  # Every spec flag shows up in its action's help text.
  local action flag
  while read -r action flag
  do
    flag="${flag%%=*}"
    if ! bash "$script" "$action" --help | grep -q -- "$flag"
    then
      printf 'flag %s of %s is missing from its help\n' "$flag" "$action" >&2
      failed=1
    fi
  done < <(sed -n 's/^flag \([^ ]*\) \([^ ]*\) .*/\1 \2/p' <<< "$spec")

  # Every global flag shows up in the main usage.
  while read -r flag
  do
    if ! bash "$script" --help | grep -q -- "$flag"
    then
      printf 'global flag %s is missing from the usage\n' "$flag" >&2
      failed=1
    fi
  done < <(sed -n 's/^global \([^ ]*\) .*/\1/p' <<< "$spec")

  # Colors must not move anything: the painted table, stripped of its
  # escape codes, is the plain one (a dropped space once shifted AGE).
  local plain painted
  plain=$'NAME  KIND  STATUS  EXPIRES  AGE\n'
  plain+=$'a  adhoc  ACTIVE  5m       1h9m\n'
  plain+=$'b  adhoc  ACTIVE  25m      2h\n'
  plain+=$'c  adhoc  ACTIVE  50m      1h9m\n'
  plain+=$'d  adhoc  BUILD   1h7m     52m\n'
  plain+=$'e  adhoc  ERROR   expired  3h\n'
  plain+=$'f  pool   ACTIVE  busy     1d2h\n'
  plain+=$'g  adhoc  ACTIVE  grace 4m  1h'
  painted=$(bash -c 'source "$1"; colorize' _ "$script" <<< "$plain" \
    | sed -E 's/\x1b\[[0-9;]*m//g')
  if [[ "$painted" != "$plain" ]]
  then
    printf 'colorize changes the table text:\n' >&2
    diff <(printf '%s\n' "$plain") <(printf '%s\n' "$painted") >&2
    failed=1
  fi

  if [[ -n "$failed" ]]
  then
    return 1
  fi
  printf 'rworker spec, dispatch, help and completions agree\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
