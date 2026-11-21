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
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mani" config path
  for config in "$config_dir"/*.yaml
  do
    [[ -f "$config" ]] || continue
    while IFS= read -r path
    do
      [[ -n "$path" ]] || continue
      resolve_path "$config_dir" "$path"
    done < <(yq eval '(.projects // {}) | to_entries | .[] | (.value.path // .key)' "$config") \
      || return 1
  done
}

# Prints the work directories of the git repositories below ROOT, one per
# line. A repository nested in another one (submodule, vendored checkout) is
# left to the outer one.
find_repos() {
  local root="$1" repo outer=""
  while IFS= read -r -d '' repo
  do
    repo="$(dirname "$repo")"
    if [[ -n "$outer" && "$repo" == "$outer"/* ]]
    then
      continue
    fi
    outer="$repo"
    printf '%s\n' "$repo"
  done < <(find "$root" -maxdepth 6 \( -name .terraform -o -name node_modules \) -prune \
    -o -name .git -prune -print0 | sort -z)
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
  local dir="$1"
  git -C "$dir" status --ignored --porcelain 2> /dev/null \
    | sed -n 's/^!! //p' \
    | grep -Ev "$BUILD_OUTPUT" \
    | head -n 1 || true
}

# Prints why DIR must not lose its repository, one reason per line: work
# that exists nowhere else.
local_work() {
  local dir="$1"
  if [[ -n "$(git -C "$dir" status --porcelain 2> /dev/null)" ]]
  then
    printf 'uncommitted changes\n'
  fi
  if [[ -n "$(ignored_files "$dir")" ]]
  then
    printf 'ignored files\n'
  fi
  if [[ -n "$(git -C "$dir" stash list 2> /dev/null)" ]]
  then
    printf 'stash\n'
  fi
  if [[ -z "$(git -C "$dir" remote 2> /dev/null)" ]]
  then
    printf 'no remote\n'
  elif [[ -n "$(git -C "$dir" log --branches --not --remotes --oneline -1 2> /dev/null)" ]]
  then
    printf 'unpushed commits\n'
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
  local root="$1" dir="$2" kind="$3" main=""
  if [[ "$dir" != "$root"/* ]]
  then
    warn "refusing to remove $dir: not below $root"
    return 1
  fi
  if [[ "$kind" == worktree ]]
  then
    main="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)"
  fi
  rm -rf --one-file-system -- "$dir" || return 1
  if [[ -n "$main" && -d "$main" ]]
  then
    git --git-dir="$main" worktree prune 2> /dev/null || true
  fi
  remove_empty_parents "$root" "$dir"
}

# Tells why DIR is kept, or nothing when it may go. Reads the options from
# the globals FORCE_DIRTY and FORCE_WORKTREES.
keep_reason() {
  local dir="$1" kind="$2" managed_file="$3" managed reasons=""
  if [[ "$PWD" == "$dir" || "$PWD" == "$dir"/* ]]
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
  if [[ "$kind" == worktree && -z "${FORCE_WORKTREES:-}" ]]
  then
    printf 'linked worktree (--worktrees)\n'
    return 0
  fi
  if [[ -z "${FORCE_DIRTY:-}" ]]
  then
    reasons="$(local_work "$dir" | paste -sd, - | sed 's/,/, /g')"
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
  local root="$1" force="$2" managed_file dir kind reason
  local removed=0 kept=0 failed=0
  managed_file="$(mktemp)" || return 1
  managed_paths | sort -u > "$managed_file" || {
    rm -f "$managed_file"
    warn "cannot read the mani configs (is yq installed?)"
    return 1
  }
  if [[ ! -s "$managed_file" ]]
  then
    rm -f "$managed_file"
    warn "no mani project found: refusing to treat every repository as unmanaged"
    return 1
  fi
  while IFS= read -r dir
  do
    dir="$(realpath -- "$dir")"
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
  done < <(find_repos "$root")
  rm -f "$managed_file"
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
  root="$(realpath -- "$root")"
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
