#!/usr/bin/env bash

usage() {
  printf 'Usage: %s [--prune-merged | --update-and-prune]\n' "${0##*/}"
}

default_branch() {
  local remote="$1" current="$2" remote_head
  if remote_head="$(git symbolic-ref "refs/remotes/$remote/HEAD" 2>/dev/null)"
  then
    printf '%s\n' "${remote_head#"refs/remotes/$remote/"}"
    return
  fi

  remote_head="$(git ls-remote --symref -- "$remote" HEAD)" || return 1
  if [[ "$remote_head" == "ref: refs/heads/"*$'\tHEAD'* ]]
  then
    remote_head="${remote_head#ref: refs/heads/}"
    printf '%s\n' "${remote_head%%$'\t'*}"
  elif [[ "$current" == main || "$current" == master || "$current" == dev ]]
  then
    printf '%s\n' "$current"
  fi
}

prune_merged() {
  local target="$1" default="$2" branches branch failed=0
  branches="$(git for-each-ref --merged="$target" \
    --format='%(if)%(worktreepath)%(then)%(else)%(refname:lstrip=2)%(end)' refs/heads)" || return 1
  while IFS= read -r branch
  do
    case "$branch" in
      ""|"$default"|main|master|dev) continue ;;
    esac
    git branch -d -- "$branch" || failed=1
  done <<< "$branches"
  return "$failed"
}

update_branch() {
  local target="$1" before after conflicts
  before="$(git rev-parse --verify HEAD)" || return 1
  git -c advice.diverging=false merge --ff-only --quiet --no-stat --autostash "$target" || return 1
  conflicts="$(git ls-files --unmerged)" || return 1
  if [[ -n "$conflicts" ]]
  then
    printf '%s: update left conflicts in the worktree\n' "$PWD" >&2
    return 1
  fi
  after="$(git rev-parse --verify HEAD)" || return 1
  if [[ "$before" != "$after" ]]
  then
    printf '%s: updated %.12s → %.12s\n' "$PWD" "$before" "$after"
  fi
}

main() {
  local mode="${1:-}" remote="${REMOTE:-origin}" current default target
  local -a refspecs
  case "$mode" in
    -h|--help) usage; return 0 ;;
    ""|--prune-merged|--update-and-prune) ;;
    *) usage >&2; return 2 ;;
  esac
  if [[ $# -gt 1 || "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]]
  then
    usage >&2
    printf 'Run this command inside a Git worktree.\n' >&2
    return 2
  fi

  current="$(git symbolic-ref --quiet HEAD)" || current=""
  current="${current#refs/heads/}"
  if [[ -z "$current" && -z "$mode" ]]
  then
    return 0
  fi
  default="$(default_branch "$remote" "$current")" || return 1
  if [[ -z "$default" ]]
  then
    printf '%s: could not determine the default branch for %s\n' "$PWD" "$remote" >&2
    return 1
  fi
  if [[ "$current" != "$default" && -z "$mode" ]]
  then
    return 0
  fi

  target="refs/remotes/$remote/$default"
  refspecs=("+refs/heads/$default:$target")
  # Only repositories that explicitly opt in may move their local latest tag.
  if git config --get-all "remote.$remote.fetch" '^\+refs/tags/latest:refs/tags/latest$' >/dev/null
  then
    refspecs+=("+refs/tags/latest:refs/tags/latest")
  fi
  git fetch --quiet --atomic --no-tags --no-prune --no-prune-tags -- "$remote" "${refspecs[@]}" || return 1

  if [[ "$mode" != --prune-merged && "$current" == "$default" ]]
  then
    update_branch "$target" || return 1
  fi
  if [[ -n "$mode" ]]
  then
    prune_merged "$target" "$default" || return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
