#!/usr/bin/env bash

# Wait for every GitHub Actions run of one commit to finish.
# Exit codes: 0 all runs succeeded, 1 a run failed, 3 timeout, 2 usage.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [COMMIT]

Poll the GitHub Actions runs of COMMIT (default: HEAD of the current repo)
until all have finished. Pending, cancelled or missing runs are not green.

Options:
  --timeout SECONDS  Give up after this long (default: 1800)
  --repo OWNER/REPO  Repository (default: the current one)
  -h, --help         Show this help
EOF
}

main() {
  local timeout=1800 repo="" sha=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --timeout)
        timeout="$2"
        shift 2
        ;;
      --repo)
        repo="$2"
        shift 2
        ;;
      *)
        sha="$1"
        shift
        ;;
    esac
  done

  sha="${sha:-$(git rev-parse HEAD)}" || return 2
  local -a gh_args=(run list --commit "$sha" --json "name,status,conclusion")
  [[ -n "$repo" ]] && gh_args+=(--repo "$repo")

  local start now runs total pending failed
  start="$(date +%s)"

  while true
  do
    runs="$(gh "${gh_args[@]}")" || return 1
    total="$(jq 'length' <<< "$runs")"
    pending="$(jq '[.[] | select(.status != "completed")] | length' <<< "$runs")"
    failed="$(jq '[.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped")] | length' <<< "$runs")"

    if [[ "$failed" -gt 0 ]]
    then
      jq -r '.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped") | "FAILED \(.name): \(.conclusion)"' <<< "$runs" >&2
      return 1
    fi
    if [[ "$total" -gt 0 && "$pending" -eq 0 ]]
    then
      printf 'All %s runs of %s succeeded\n' "$total" "${sha:0:9}"
      return 0
    fi

    now="$(date +%s)"
    if (( now - start > timeout ))
    then
      printf 'Timeout: %s runs, %s pending for %s\n' "$total" "$pending" "${sha:0:9}" >&2
      return 3
    fi
    sleep 20
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
