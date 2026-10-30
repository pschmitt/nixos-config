#!/usr/bin/env bash

# Sync a working tree to a build host and optionally run a command there.
# Evaluations and builds must not run on the machine the agent runs on.

REMOTE_HOST="${REMOTE_BUILD_HOST:-rofl-13}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] SRC [-- COMMAND...]

Rsync SRC to ~/build/NAME on the build host (without .git, so path flakes see
untracked files) and run COMMAND there from that directory.

Options:
  --host HOST      Build host (default: $REMOTE_HOST; use rofl-14 as the
                   alternative)
  --name NAME      Remote directory below ~/build (default: basename of SRC
                   without .git; add a run-specific suffix when agents share
                   the host)
  --private DIR    Also sync a local nixos-config-private checkout to
                   ~/build/NAME-private. @PRIVATE@ in COMMAND is replaced by
                   its remote path, for example
                   --override-input nixos-config-private path:@PRIVATE@
  -h, --help       Show this help
EOF
}

sync_tree() {
  local src="$1" host="$2" dest="$3"

  ssh -- "$host" "mkdir -p ~/build/$dest && rm -rf ~/build/$dest/.git" || return 1
  rsync -az --delete \
    --exclude .git --exclude target --exclude 'result*' --exclude .direnv \
    --exclude node_modules --exclude .terraform \
    "${src%/}/" "$host:build/$dest/" || return 1
}

main() {
  local host="$REMOTE_HOST" name="" private="" src=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --host)
        host="$2"
        shift 2
        ;;
      --name)
        name="$2"
        shift 2
        ;;
      --private)
        private="$2"
        shift 2
        ;;
      --)
        break
        ;;
      *)
        src="$1"
        shift
        ;;
    esac
  done

  if [[ -z "$src" ]]
  then
    printf 'Missing SRC\n' >&2
    usage >&2
    return 2
  fi
  [[ "${1:-}" == "--" ]] && shift

  if [[ -z "$name" ]]
  then
    name="$(basename "$(realpath "$src")")"
    name="${name%.git}"
  fi

  sync_tree "$src" "$host" "$name" || return 1
  if [[ -n "$private" ]]
  then
    sync_tree "$private" "$host" "$name-private" || return 1
  fi

  if [[ $# -gt 0 ]]
  then
    local cmd="$*"
    cmd="${cmd//@PRIVATE@/\$HOME/build/$name-private}"
    ssh -- "$host" "cd ~/build/$name && $cmd"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
