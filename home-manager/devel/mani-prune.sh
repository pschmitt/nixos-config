#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Remove the git repositories below ~/devel that no mani config manages.
Without --force nothing is removed: the repositories are listed, with what
would happen to each of them.

A repository that holds work existing nowhere else (uncommitted or untracked
changes, ignored files that are not mere build output, commits on no remote,
stashes, no remote at all) is kept unless --dirty is given. Linked worktrees are kept unless --worktrees is given.
A primary checkout with registered linked worktrees is always kept.
A repository that contains a managed project, or the current directory, is
always kept.

Options:
  -f, --force      remove the repositories
      --dirty      also remove repositories with local work
      --worktrees  also remove linked worktrees
  -d, --dir DIR    directory to scan (default: ~/devel)
  -h, --help       show this help

The managed projects are the "path" of every project of
\${XDG_CONFIG_HOME:-~/.config}/mani/*.yaml.
EOF
}

warn() {
  printf '%s: %s\n' "$(basename "$0")" "$*" >&2
}

# Ignored paths that are build output or caches, not someone's data.
BUILD_OUTPUT='(^|/)(target|node_modules|\.direnv|result|result-[a-z]+|__pycache__|\.venv|venv|\.terraform|dist|build|\.mypy_cache|\.pytest_cache|\.ruff_cache|\.cache|\.gradle|\.idea|\.vscode)(/|$)|\.(pyc|pyo|swp)$|\.egg-info/?$|^\.pre-commit-config\.yaml$'

# Prints the absolute path PATH_ARG of a mani project, "~" expanded and a
# relative one taken from the directory of its config.
resolve_path() {
  local base="$1" path="$2"
  # shellcheck disable=SC2088 # a literal "~" is what a mani config holds
  case "$path" in
    "~"|"~/"*)
      path="${HOME}${path#\~}"
      ;;
    /*)
      ;;
    *)
      path="${base}/${path}"
      ;;
  esac
  realpath -m -- "$path"
}

# Prints the absolute path of every project of every mani config, one per line.
managed_paths() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mani" config path paths
  for config in "$config_dir"/*.yaml
  do
    [[ -f "$config" ]] || continue
    paths="$(yq eval '(.projects // {}) | to_entries | .[] | (.value.path // .key)' "$config")" || return 1
    while IFS= read -r path
    do
      [[ -n "$path" ]] || continue
      resolve_path "$config_dir" "$path" || return 1
    done <<< "$paths"
  done
}

# Filters sorted, NUL-delimited .git paths to top-level worktree directories.
# A nested repository is left to the outer one.
find_repos() {
  local repo outer=""
  while IFS= read -r -d '' repo
  do
    repo="${repo%/.git}"
    if [[ -n "$outer" && "$repo" == "$outer"/* ]]
    then
      continue
    fi
    outer="$repo"
    printf '%s\0' "$repo"
  done
}

# Tells what kind of checkout DIR is: repo, worktree or submodule.
repo_kind() {
  local dir="$1" gitdir
  if [[ -d "$dir/.git" ]]
  then
    printf 'repo\n'
    return 0
  fi
  gitdir="$(sed -n 's/^gitdir: //p' "$dir/.git" 2> /dev/null || true)"
  case "$gitdir" in
    */worktrees/*)
      printf 'worktree\n'
      ;;
    *)
      printf 'submodule\n'
      ;;
  esac
}

# Prints the first ignored file or directory of DIR that is not plain build
# output: a .env, a data directory, results that nothing else regenerates.
ignored_files() {
  local status="$1"
  sed -n 's/^!! //p' <<< "$status" \
    | grep -Ev "$BUILD_OUTPUT" \
    | head -n 1 || true
}

# Prints why DIR must not lose its repository, one reason per line: work
# that exists nowhere else.
local_work() {
  local dir="$1" status stashes remotes commits
  status="$(git -C "$dir" status --ignored --untracked-files=normal --ignore-submodules=none --porcelain)" || return 1
  stashes="$(git -C "$dir" stash list)" || return 1
  remotes="$(git -C "$dir" remote)" || return 1
  if grep -qEv '^!! |^$' <<< "$status"
  then
    printf 'uncommitted changes\n'
  fi
  if [[ -n "$(ignored_files "$status")" ]]
  then
    printf 'ignored files\n'
  fi
  if [[ -n "$stashes" ]]
  then
    printf 'stash\n'
  fi
  if [[ -z "$remotes" ]]
  then
    printf 'no remote\n'
  else
    commits="$(git -C "$dir" rev-list --max-count=1 HEAD --branches --tags --not --remotes)" || return 1
    if [[ -n "$commits" ]]
    then
      printf 'unpushed commits\n'
    fi
  fi
}

# Removes the now empty directories above PATH_ARG, up to but not including ROOT.
remove_empty_parents() {
  local root="$1" dir
  dir="$(dirname "$2")"
  while [[ "$dir" == "$root"/* ]]
  do
    rmdir -- "$dir" 2> /dev/null || break
    dir="$(dirname "$dir")"
  done
}

remove_repo() {
  local root="$1" dir="$2" kind="$3" common_dir
  local -a worktree_options=()
  if [[ "$dir" != "$root"/* ]]
  then
    warn "refusing to remove $dir: not below $root"
    return 1
  fi
  if [[ "$kind" == worktree ]]
  then
    common_dir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)" || return 1
    if [[ -n "${FORCE_DIRTY:-}" ]]
    then
      worktree_options+=(--force)
    fi
    git --git-dir="$common_dir" worktree remove "${worktree_options[@]}" -- "$dir" || return 1
  else
    rm -rf --one-file-system -- "$dir" || return 1
  fi
  remove_empty_parents "$root" "$dir"
}

# Tells why DIR is kept, or nothing when it may go. Reads the options from
# the globals FORCE_DIRTY and FORCE_WORKTREES.
keep_reason() {
  local dir="$1" kind="$2" managed_file="$3" managed reasons worktrees
  if [[ "$physical_cwd" == "$dir" || "$physical_cwd" == "$dir"/* ]]
  then
    printf 'current directory\n'
    return 0
  fi
  while IFS= read -r managed
  do
    if [[ "$managed" == "$dir"/* ]]
    then
      printf 'contains a managed project\n'
      return 0
    fi
  done < "$managed_file"
  if ! worktrees="$(git -C "$dir" worktree list --porcelain)"
  then
    printf 'cannot inspect worktrees\n'
    return 0
  fi
  if [[ "$kind" == repo && "$worktrees" == *$'\nworktree '* ]]
  then
    printf 'primary checkout has linked worktrees\n'
    return 0
  fi
  if [[ "$kind" == worktree && -z "${FORCE_WORKTREES:-}" ]]
  then
    printf 'linked worktree (--worktrees)\n'
    return 0
  fi
  if [[ -z "${FORCE_DIRTY:-}" ]]
  then
    if ! reasons="$(local_work "$dir")"
    then
      printf 'cannot inspect local work\n'
      return 0
    fi
    reasons="$(paste -sd, - <<< "$reasons" | sed 's/,/, /g')"
    if [[ -n "$reasons" ]]
    then
      printf '%s (--dirty)\n' "$reasons"
    fi
  fi
}

# Whether DIR is a managed project or lies inside one.
is_managed() {
  local dir="$1" managed_file="$2" managed
  while IFS= read -r managed
  do
    if [[ "$dir" == "$managed" || "$dir" == "$managed"/* ]]
    then
      return 0
    fi
  done < "$managed_file"
  return 1
}

prune() {
  local root="$1" force="$2" managed_file repos_file dir kind reason physical_cwd
  physical_cwd="$(pwd -P)" || return 1
  local removed=0 kept=0 failed=0
  managed_file="$(mktemp)" || return 1
  if ! (set -o pipefail; managed_paths | sort -u) > "$managed_file"
  then
    rm -f "$managed_file"
    warn "cannot read the mani configs (is yq installed?)"
    return 1
  fi
  if [[ ! -s "$managed_file" ]]
  then
    rm -f "$managed_file"
    warn "no mani project found: refusing to treat every repository as unmanaged"
    return 1
  fi
  repos_file="$(mktemp)" || {
    rm -f "$managed_file"
    return 1
  }
  if ! (set -o pipefail; find "$root" -maxdepth 6 \( -name .terraform -o -name node_modules \) -prune \
    -o -name .git -prune -print0 | sort -z | find_repos) > "$repos_file"
  then
    rm -f "$managed_file" "$repos_file"
    warn "cannot scan $root"
    return 1
  fi
  while IFS= read -r -d '' dir
  do
    kind="$(repo_kind "$dir")"
    if [[ "$kind" == submodule ]] || is_managed "$dir" "$managed_file"
    then
      continue
    fi
    reason="$(keep_reason "$dir" "$kind" "$managed_file")"
    if [[ -n "$reason" ]]
    then
      printf 'keep    %s  (%s)\n' "$dir" "$reason"
      kept=$((kept + 1))
    elif [[ -z "$force" ]]
    then
      printf 'remove  %s\n' "$dir"
      removed=$((removed + 1))
    elif remove_repo "$root" "$dir" "$kind"
    then
      printf 'removed %s\n' "$dir"
      removed=$((removed + 1))
    else
      warn "could not remove $dir"
      failed=$((failed + 1))
    fi
  done < "$repos_file"
  rm -f "$managed_file" "$repos_file"
  if [[ -z "$force" ]]
  then
    printf '%d to remove, %d kept. Nothing was removed: run with --force.\n' "$removed" "$kept"
  else
    printf '%d removed, %d kept, %d failed.\n' "$removed" "$kept" "$failed"
  fi
  (( failed == 0 ))
}

main() {
  local root="$HOME/devel" force=""
  FORCE_DIRTY=""
  FORCE_WORKTREES=""
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -f|--force)
        force=1
        shift
        ;;
      --dirty)
        FORCE_DIRTY=1
        shift
        ;;
      --worktrees)
        FORCE_WORKTREES=1
        shift
        ;;
      -d|--dir)
        if [[ -z "${2:-}" ]]
        then
          warn "$1 needs a directory"
          usage >&2
          return 2
        fi
        root="$2"
        shift 2
        ;;
      *)
        warn "unknown argument: $1"
        usage >&2
        return 2
        ;;
    esac
  done
  if [[ ! -d "$root" ]]
  then
    warn "not a directory: $root"
    return 2
  fi
  root="$(realpath -- "$root")" || return 1
  if [[ "$root" == / || "$root" == "$HOME" ]]
  then
    warn "refusing to scan $root"
    return 2
  fi
  prune "$root" "$force"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
