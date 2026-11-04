#!/usr/bin/env bash

# Wait for every GitHub Actions run (or GitLab pipeline) of one commit to finish.
# Exit codes: 0 all runs succeeded, 1 a run failed, 2 usage, 3 timeout,
# 4 no runs were ever registered for the commit, 5 runs were cancelled and none
# failed (a newer commit replaced them, or someone cancelled them), 6 the forge
# could not be queried.

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [COMMIT]

Poll the GitHub Actions runs or GitLab pipelines of COMMIT (default: HEAD of
the current repo) until all have finished, and print one summary line. Start it once per push,
as a background command, and do other work or end your turn while it runs.

Options:
  --follow           Follow the remote head of the current branch: when a new
                     commit is pushed, switch to it instead of reporting on
                     the old one
  --timeout SECONDS  Give up after this long (default: 1800)
  --grace SECONDS    Wait this long for runs to be registered before exiting
                     with 4, or for a failing forge API to recover before
                     exiting with 6 (default: 120)
  --forge NAME       github or gitlab (default: github for a github.com
                     origin, gitlab otherwise; required outside a checkout)
  --repo OWNER/REPO  Repository (default: the current one)
  -h, --help         Show this help
EOF
}

remote_head() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)" || return 1
  git ls-remote origin "refs/heads/${branch}" | cut -f1
}

detect_forge() {
  local url
  if ! url="$(git remote get-url origin 2>/dev/null)"
  then
    printf 'Cannot detect the forge without an origin remote: pass --forge\n' >&2
    return 1
  fi

  case "$url" in
    *github.com*) echo github ;;
    *) echo gitlab ;;
  esac
}

# Print the runs of $1 (sha) as JSON: [{name,status,conclusion,databaseId}],
# status being "completed" or not, conclusion "success" when green.
fetch_runs() {
  local sha="$1" project
  if [[ "$forge" == github ]]
  then
    local -a gh_args=(run list --commit "$sha" --json "name,status,conclusion,databaseId")
    [[ -n "$repo" ]] && gh_args+=(--repo "$repo")
    gh "${gh_args[@]}"
    return
  fi

  project=":fullpath"
  [[ -n "$repo" ]] && project="$(jq -rn --arg r "$repo" '$r | @uri')"
  glab api "projects/${project}/pipelines?sha=${sha}&per_page=100" | jq '
    map({
      name: "pipeline \(.ref)",
      status: (if (.status | IN("success", "failed", "canceled", "skipped", "manual")) then "completed" else .status end),
      conclusion: .status,
      databaseId: .id
    })'
}

# Drop a cancelled run when the same workflow has another run on this commit: it
# was replaced, so only the other run counts.
drop_replaced() {
  jq '
    def cancelled: .conclusion == "cancelled" or .conclusion == "canceled";
    group_by(.name)
    | map(if any(.[]; cancelled | not) then map(select(cancelled | not)) else . end)
    | add // []'
}

main() {
  local timeout=1800 grace=120 follow=0 repo="" sha="" forge=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --follow)
        follow=1
        shift
        ;;
      --timeout)
        timeout="$2"
        shift 2
        ;;
      --grace)
        grace="$2"
        shift 2
        ;;
      --forge)
        forge="$2"
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
  forge="${forge:-$(detect_forge)}" || return 2

  local start last_ok now runs total pending failed cancelled head
  start="$(date +%s)"
  last_ok="$start"

  while true
  do
    if [[ "$follow" -eq 1 ]]
    then
      head="$(remote_head)"
      if [[ -n "$head" && "$head" != "$sha" ]]
      then
        printf 'Remote head moved to %s, following\n' "${head:0:9}" >&2
        sha="$head"
        start="$(date +%s)"
      fi
    fi

    # An API error says nothing about the runs: never read it as "no runs".
    if ! runs="$(fetch_runs "$sha" | drop_replaced)" || [[ -z "$runs" ]]
    then
      now="$(date +%s)"
      if (( now - last_ok > grace ))
      then
        printf 'Cannot query %s for %s: API errors for %ss, CI state unknown\n' "$forge" "${sha:0:9}" "$grace" >&2
        return 6
      fi
      sleep 20
      continue
    fi
    last_ok="$(date +%s)"

    total="$(jq 'length' <<< "$runs")"
    pending="$(jq '[.[] | select(.status != "completed")] | length' <<< "$runs")"
    failed="$(jq '[.[] | select(.status == "completed" and (.conclusion | IN("success", "skipped", "cancelled", "canceled") | not))] | length' <<< "$runs")"
    cancelled="$(jq '[.[] | select(.conclusion == "cancelled" or .conclusion == "canceled")] | length' <<< "$runs")"

    if [[ "$failed" -gt 0 ]]
    then
      printf 'FAILED %s of %s runs of %s\n' "$failed" "$total" "${sha:0:9}" >&2
      jq -r '.[] | select(.status == "completed" and (.conclusion | IN("success", "skipped", "cancelled", "canceled") | not)) | "  \(.name): \(.conclusion) (run \(.databaseId))"' <<< "$runs" >&2
      if [[ "$forge" == github ]]
      then
        printf 'Inspect with: gh run view RUN_ID --log-failed | tail -n 40\n' >&2
      else
        printf 'Inspect with: glab ci trace PIPELINE_JOB | tail -n 40 (glab ci view PIPELINE_ID lists jobs)\n' >&2
      fi
      return 1
    fi
    if [[ "$cancelled" -gt 0 ]]
    then
      head=""
      [[ -z "$repo" ]] && head="$(remote_head)"
      if [[ -n "$head" && "$head" != "$sha" ]]
      then
        if [[ "$follow" -eq 1 ]]
        then
          continue
        fi
        printf 'SUPERSEDED %s of %s runs of %s cancelled, none failed; branch head is now %s\n' "$cancelled" "$total" "${sha:0:9}" "${head:0:9}" >&2
        return 5
      fi
      if [[ "$pending" -eq 0 ]]
      then
        printf 'CANCELLED %s of %s runs of %s, none failed, no newer commit on the branch\n' "$cancelled" "$total" "${sha:0:9}" >&2
        return 5
      fi
    fi
    if [[ "$total" -gt 0 && "$pending" -eq 0 ]]
    then
      printf 'All %s runs of %s succeeded\n' "$total" "${sha:0:9}"
      return 0
    fi

    now="$(date +%s)"
    if [[ "$total" -eq 0 ]] && (( now - start > grace ))
    then
      printf 'No runs registered for %s after %ss (no workflow for this push?)\n' "${sha:0:9}" "$grace" >&2
      return 4
    fi
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
  set -o pipefail
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
