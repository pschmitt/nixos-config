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
    in_main && after_shift && /^    [a-z][a-z-]*\)$/ { gsub(/[ )]/, ""); print }
    in_main && /^}$/ { exit }
  ' "$1" | sort -u
}

# Actions action_help() documents.
helped() {
  awk '
    /^action_help\(\)/ { in_help = 1 }
    in_help && /^    [a-z][a-z-]*\)$/ { gsub(/[ )]/, ""); print }
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
