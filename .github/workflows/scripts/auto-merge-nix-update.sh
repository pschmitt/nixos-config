#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") PR_NUMBER PACKAGE [EXPECTED_HEAD]
EOF
}

check_and_merge() {
  local pr_number="$1"
  local package="$2"
  local expected_head="${3:-}"
  local current_head
  local checks
  local result

  current_head="$(gh pr view "$pr_number" --json headRefOid --jq .headRefOid)" || return
  if [[ -n "$expected_head" && "$current_head" != "$expected_head" ]]
  then
    printf 'PR head changed; leaving it for the next check.\n'
    return 0
  fi
  # gh returns 8 for pending checks and 1 for failed checks, both valid JSON.
  local check_status=0
  checks="$(gh pr checks "$pr_number" --json name,bucket,workflow)" || check_status=$?
  if (( check_status != 0 && check_status != 1 && check_status != 8 ))
  then
    return "$check_status"
  fi
  if ! jq -e 'type == "array"' <<<"$checks" >/dev/null
  then
    return 1
  fi
  result="$(jq -r \
    --arg package "$package" \
    '
      def check_buckets($workflow; $name):
        [.[] | select(.workflow == $workflow and .name == $name) | .bucket];

      def package_buckets($system):
        [.[] | select(
          .workflow == "Nix build"
          and (
            .name == ("build " + $package + " (" + $system + ")")
            or .name == ("build-nonfree " + $package + " (" + $system + ")")
          )
        ) | .bucket];

      # x86_64-linux is built by nixbot (a GitHub App check run, no
      # workflow); GitHub Actions builds the aarch64-linux packages.
      [
        check_buckets("Nix build"; "setup-matrix"),
        check_buckets("Statix Lint"; "lint"),
        check_buckets(""; "nixbot/nix-build"),
        package_buckets("aarch64-linux")
      ] as $required
      | if any($required[]; any(.[]; . == "fail" or . == "cancel")) then
          "fail"
        elif all($required[]; length > 0 and all(.[]; . == "pass")) then
          "pass"
        else
          "pending"
        end
    ' <<<"$checks")"

  case "$result" in
    pass)
      printf 'Required checks passed for PR #%s at %s; merging.\n' "$pr_number" "$current_head"
      gh pr merge "$pr_number" \
        --squash \
        --delete-branch \
        --match-head-commit "$current_head" || return
      return 0
      ;;
    fail)
      printf 'A required check failed for PR #%s; leaving it open.\n' "$pr_number" >&2
      return 0
      ;;
    pending)
      printf 'Package checks pending for PR #%s; a later event will retry.\n' "$pr_number"
      return 0
      ;;
    *)
      printf 'Unexpected check state: %s\n' "$result" >&2
      return 1
      ;;
  esac
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]
  then
    usage
    return 0
  fi

  if [[ $# -lt 2 || $# -gt 3 ]]
  then
    usage >&2
    return 2
  fi

  check_and_merge "$1" "$2" "${3:-}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
