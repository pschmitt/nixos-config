#!/usr/bin/env bash
# Tests for mani-prune.sh. Everything happens in a temporary HOME with real
# (small) git repositories; nothing outside it is read or touched. The script
# runs with errexit, nounset and pipefail, like under writeShellApplication.

usage() {
  cat <<EOF2
Usage: $(basename "$0") [-h|--help]

Run the mani-prune.sh scenarios in a temporary HOME. Needs git and yq.
EOF2
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/mani-prune.sh"
PASS=0
FAIL=0
TMP=""

pass() {
  PASS=$((PASS + 1))
  printf 'ok   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
  printf -- '--- output\n%s\n---\n' "${OUT:-}"
}

# git with a fixed identity, no signing and none of the user's configuration.
tgit() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.org \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.org \
    git -c init.defaultBranch=main -c commit.gpgsign=false "$@"
}

# mkrepo NAME: a clean clone of its own bare remote below ~/devel.
mkrepo() {
  local dir="$HOME/devel/$1"
  mkdir -p "$(dirname "$dir")" "$TMP/remotes"
  tgit init -q --bare "$TMP/remotes/${1//\//_}.git"
  tgit clone -q "$TMP/remotes/${1//\//_}.git" "$dir" 2> /dev/null
  printf 'x\n' > "$dir/file"
  tgit -C "$dir" add file
  tgit -C "$dir" commit -q -m init
  tgit -C "$dir" push -q origin main 2> /dev/null
}

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME/devel" "$XDG_CONFIG_HOME/mani"
  mkrepo private/managed.git
  mkrepo work/also-managed.git
  mkrepo private/stray.git
  mkrepo misc/deep/stray2.git
  cat > "$XDG_CONFIG_HOME/mani/private.yaml" <<'YAML'
projects:
  managed:
    path: ~/devel/private/managed.git
YAML
  cat > "$XDG_CONFIG_HOME/mani/work.yaml" <<'YAML'
projects:
  also-managed:
    path: ~/devel/work/also-managed.git
YAML
}

teardown() {
  rm -rf "$TMP"
}

# run ARGS...: sets OUT and RC; cwd outside ~/devel.
run() {
  RC=0
  OUT="$(cd "$TMP" && bash -euo pipefail "$SCRIPT" "$@" 2>&1)" || RC=$?
}

exists() {
  [[ -d "$HOME/devel/$1" ]]
}

expect_out() {
  [[ "$OUT" == *"$2"* ]] || {
    fail "$1" "output lacks '$2'"
    return 1
  }
}

expect_no_out() {
  [[ "$OUT" != *"$2"* ]] || {
    fail "$1" "output has unexpected '$2'"
    return 1
  }
}

expect_rc() {
  [[ "$RC" == "$2" ]] || {
    fail "$1" "exit code $RC, wanted $2"
    return 1
  }
}

test_dry_run_lists_and_removes_nothing() {
  local n=dry-run
  run
  expect_rc "$n" 0 \
    && expect_out "$n" "remove  $HOME/devel/private/stray.git" \
    && expect_out "$n" "remove  $HOME/devel/misc/deep/stray2.git" \
    && expect_no_out "$n" "managed.git" \
    && expect_out "$n" "2 to remove, 0 kept" \
    && exists private/stray.git && exists misc/deep/stray2.git \
    && pass "$n"
}

test_force_removes_unmanaged_only() {
  local n=force
  run --force
  expect_rc "$n" 0 \
    && expect_out "$n" "2 removed, 0 kept, 0 failed" \
    && ! exists private/stray.git && ! exists misc/deep/stray2.git \
    && exists private/managed.git && exists work/also-managed.git \
    && pass "$n"
  # The directory that only held a removed repository goes away too.
  if [[ -d "$HOME/devel/misc" ]]
  then
    fail force-empty-parents "$HOME/devel/misc is still there"
  else
    pass force-empty-parents
  fi
}

test_local_work_is_kept() {
  local n=dirty
  printf 'y\n' >> "$HOME/devel/private/stray.git/file"
  tgit -C "$HOME/devel/misc/deep/stray2.git" commit -q --allow-empty -m local
  mkdir -p "$HOME/devel/misc/norem"
  tgit init -q "$HOME/devel/misc/norem"
  printf 'x\n' > "$HOME/devel/misc/norem/f"
  tgit -C "$HOME/devel/misc/norem" add f
  tgit -C "$HOME/devel/misc/norem" commit -q -m c
  run --force
  expect_rc "$n" 0 \
    && expect_out "$n" "keep    $HOME/devel/private/stray.git  (uncommitted changes (--dirty))" \
    && expect_out "$n" "keep    $HOME/devel/misc/deep/stray2.git  (unpushed commits (--dirty))" \
    && expect_out "$n" "keep    $HOME/devel/misc/norem  (no remote (--dirty))" \
    && exists private/stray.git && exists misc/deep/stray2.git && exists misc/norem \
    && pass "$n-kept"
  run --force --dirty
  expect_rc "$n" 0 \
    && ! exists private/stray.git && ! exists misc/deep/stray2.git && ! exists misc/norem \
    && exists private/managed.git \
    && pass "$n-forced"
}

test_stash_counts_as_local_work() {
  local n=stash
  printf 'z\n' >> "$HOME/devel/private/stray.git/file"
  tgit -C "$HOME/devel/private/stray.git" stash -q
  run
  expect_out "$n" "keep    $HOME/devel/private/stray.git  (stash (--dirty))" && pass "$n"
}

test_worktrees_are_kept_unless_asked() {
  local n=worktree
  tgit -C "$HOME/devel/private/managed.git" worktree add -q "$HOME/devel/private/managed.worktree" -b wt
  run --force
  expect_out "$n" "keep    $HOME/devel/private/managed.worktree  (linked worktree (--worktrees))" \
    && exists private/managed.worktree \
    && pass "$n-kept"
  run --force --worktrees
  expect_rc "$n" 0 \
    && ! exists private/managed.worktree \
    && ! tgit -C "$HOME/devel/private/managed.git" worktree list --porcelain | grep -q managed.worktree \
    && pass "$n-removed-and-pruned"
}

test_parent_of_a_managed_project_is_kept() {
  local n=contains-managed
  mkdir -p "$HOME/devel/group"
  tgit init -q "$HOME/devel/group"
  mkrepo group/inner.git
  printf '  inner:\n    path: ~/devel/group/inner.git\n' >> "$XDG_CONFIG_HOME/mani/private.yaml"
  run --force
  expect_out "$n" "keep    $HOME/devel/group  (contains a managed project)" \
    && exists group/inner.git \
    && pass "$n"
}

test_nested_repo_of_a_managed_project_is_ignored() {
  local n=nested
  mkrepo private/managed.git/vendor/lib
  run --force
  expect_no_out "$n" "vendor" && exists private/managed.git/vendor/lib && pass "$n"
}

test_current_directory_is_kept() {
  local n=cwd
  RC=0
  OUT="$(cd "$HOME/devel/private/stray.git" && bash -euo pipefail "$SCRIPT" --force 2>&1)" || RC=$?
  expect_out "$n" "keep    $HOME/devel/private/stray.git  (current directory)" \
    && exists private/stray.git && pass "$n"
}

test_no_mani_config_refuses() {
  local n=no-config
  rm -f "$XDG_CONFIG_HOME"/mani/*.yaml
  run --force
  expect_rc "$n" 1 && expect_out "$n" "no mani project found" \
    && exists private/stray.git && pass "$n"
}

test_arguments() {
  local n
  run --help
  n="help"
  expect_rc "$n" 0 && expect_out "$n" "Usage:" && pass "$n"
  run --bogus
  n="unknown-arg"
  expect_rc "$n" 2 && expect_out "$n" "unknown argument" && pass "$n"
  run --dir "$HOME"
  n="refuse-home"
  expect_rc "$n" 2 && expect_out "$n" "refusing to scan" && pass "$n"
  run --dir "$TMP/nope"
  n="missing-dir"
  expect_rc "$n" 2 && expect_out "$n" "not a directory" && pass "$n"
  run --dir
  n="dir-needs-value"
  expect_rc "$n" 2 && pass "$n"
}

main() {
  local t
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac
  for t in $(compgen -A function test_)
  do
    setup
    "$t"
    teardown
  done
  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  (( FAIL == 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
