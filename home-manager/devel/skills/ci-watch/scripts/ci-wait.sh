#!/usr/bin/env bash

# Wait for every GitHub Actions run (or GitLab pipeline) of one commit to finish.
# Exit codes: 0 all runs succeeded, 1 a run failed, 2 usage, 3 timeout,
# 4 no runs were ever registered for the commit.

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
                     with 4 (default: 120)
  --forge NAME       github or gitlab (default: github for a github.com
                     origin, gitlab otherwise)
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
  case "$(git remote get-url origin 2>/dev/null)" in
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
  forge="${forge:-$(detect_forge)}"

  local start now runs total pending failed head
  start="$(date +%s)"

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

    runs="$(fetch_runs "$sha")" || return 1
    total="$(jq 'length' <<< "$runs")"
    pending="$(jq '[.[] | select(.status != "completed")] | length' <<< "$runs")"
    failed="$(jq '[.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped")] | length' <<< "$runs")"

    if [[ "$failed" -gt 0 ]]
    then
      printf 'FAILED %s of %s runs of %s\n' "$failed" "$total" "${sha:0:9}" >&2
      jq -r '.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped") | "  \(.name): \(.conclusion) (run \(.databaseId))"' <<< "$runs" >&2
      if [[ "$forge" == github ]]
      then
        printf 'Inspect with: gh run view RUN_ID --log-failed | tail -n 40\n' >&2
      else
        printf 'Inspect with: glab ci trace PIPELINE_JOB | tail -n 40 (glab ci view PIPELINE_ID lists jobs)\n' >&2
      fi
      return 1
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
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
