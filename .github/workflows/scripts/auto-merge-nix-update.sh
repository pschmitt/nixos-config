#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") PR_NUMBER PACKAGE
EOF
}

wait_for_checks_and_merge() {
  local pr_number="$1"
  local package="$2"
  local deadline=$((SECONDS + 18000))
  local current_head
  local checks
  local result

  while (( SECONDS < deadline ))
  do
    current_head="$(gh pr view "$pr_number" --json headRefOid --jq .headRefOid)"
    checks="$(gh pr checks "$pr_number" --json name,bucket,workflow)"
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

        [
          check_buckets("Nix build"; "setup-matrix"),
          check_buckets("Statix Lint"; "lint"),
          package_buckets("x86_64-linux"),
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
          --match-head-commit "$current_head"
        return 0
        ;;
      fail)
        printf 'A required check failed for PR #%s; leaving it open.\n' "$pr_number" >&2
        return 1
        ;;
      pending)
        printf 'Waiting for package checks on PR #%s.\n' "$pr_number"
        sleep 20
        ;;
      *)
        printf 'Unexpected check state: %s\n' "$result" >&2
        return 1
        ;;
    esac
  done

  printf 'Timed out waiting for package checks on PR #%s; leaving it open.\n' "$pr_number" >&2
  return 1
}

main() {
  if [[ $# -ne 2 ]]
  then
    usage >&2
    return 2
  fi

  wait_for_checks_and_merge "$1" "$2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
