#!/usr/bin/env bash
set -euo pipefail

# Requirements (binaries):
# - coreutils: find, sort, sha256sum, mktemp, cat, printf
# - util-linux: readlink, realpath
# - cpio: cpio (only for initrd image mode)
# - gzip or zstd: gzip/zstd (only for initrd image mode)
# - openssh-client: ssh (remote modes)
# - bash: for local and remote shells
# - tee (only if you re-enable streaming outputs)
# Remote live-root mode: needs bash + find + sort + sha256sum (pkgs.bashInteractive pkgs.coreutils pkgs.findutils).
# Remote initrd-image mode: additionally needs cpio + gzip/zstd (pkgs.cpio pkgs.gzip/pkgs.zstd).
# Paranoid mode: pushes a tiny bundle to /run/initrd-checksum/bin on the remote host and prepends it to PATH for all remote actions.
#
# Nix quick refs (packages providing the above):
#   pkgs.coreutils, pkgs.findutils, pkgs.util-linux, pkgs.cpio,
#   pkgs.gzip, pkgs.zstd, pkgs.openssh, pkgs.bashInteractive

usage() {
  cat <<EOF
Usage:
  $0 checksum [--host HOST] [--ssh-user USER] [--initrd[=PATH]] [--diff FILE] [-q|--quiet] [--paranoid]
  $0 diff FILE1 FILE2

Modes:
  checksum (default)  Detects initrd vs normal, hashes accordingly.
    - With --host: ssh to HOST; auto-detect initrd via /etc/initrd-release.
    - With --initrd: force hashing of an initrd image (default path: /run/current-system/initrd).
    - With --diff FILE: after hashing, show diff vs FILE (sorted).
    - With --quiet: suppress checksum stdout (still logs and runs diff if provided).
    - With --paranoid: push a minimal binary bundle to /run/initrd-checksum/bin on the remote host and prepend to PATH.

  diff                 Unified diff of two existing checksum files (sorted).

Output:
  SHA256_HASH  /absolute/path  (for checksum)
  unified diff (for diff)

Notes:
  - Live root measurement expects root privileges.
  - SSH defaults to user "root". Override with --ssh-user/--ssh-username/-l.
EOF
}

ssh() {
  log_debug "\$ ssh $*"
  command ssh "$@"
}

setup_colors() {
  if [[ -t 1 ]]
  then
    COLOR_DEBUG=$'\033[1;35m'
    COLOR_INFO=$'\033[1;34m'
    COLOR_WARN=$'\033[1;33m'
    COLOR_ERR=$'\033[1;31m'
    COLOR_OK=$'\033[1;32m'
    COLOR_RESET=$'\033[0m'
  else
    COLOR_INFO=""
    COLOR_WARN=""
    COLOR_ERR=""
    COLOR_OK=""
    COLOR_RESET=""
  fi
}

log() {
  local level msg color
  level=$1
  msg=$2
  color=$3
  printf '%s%s%s %s\n' "$color" "$level" "$COLOR_RESET" "$msg" >&2
}

log_debug() {
  log DBG "$1" "$COLOR_DEBUG"
}

log_info() {
  log INF "$1" "$COLOR_INFO"
}

log_warn() {
  log WRN "$1" "$COLOR_WARN"
}

log_err() {
  log ERR "$1" "$COLOR_ERR"
}

log_ok() {
  log OK "$1" "$COLOR_OK"
}

EXIT_CMDS=()

run_exit_traps() {
  local cmd
  for cmd in "${EXIT_CMDS[@]}"
  do
    eval "$cmd"
  done
}

add_exit_trap() {
  local new_cmd="$1"
  EXIT_CMDS+=("$new_cmd")
  trap run_exit_traps EXIT
}

SSH_OPTS=(
  -o ControlMaster=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o StrictHostKeyChecking=no
)

IGNORE_RELS=(
  "etc/machine-id"
  "var/empty/.bash_history"
  "etc/ssh/initrd/ssh_host_"
  ".initrd-secrets/etc/ssh/initrd/ssh_host_"
)

REMOTE_PATH_PREFIX=""

resolve_initrd_path() {
  local path resolved
  path=$1

  if resolved=$(readlink -f "$path" 2>/dev/null)
  then
    printf '%s\n' "$resolved"
    return
  fi

  if resolved=$(realpath "$path" 2>/dev/null)
  then
    printf '%s\n' "$resolved"
    return
  fi

  printf '%s\n' "$path"
}

hash_tree() {
  local root
  root=$1

  cd "$root"

  find . -xdev \
    \( -path ./dev -o -path ./proc -o -path ./sys -o -path ./run -o -path ./tmp \) -prune -o \
    -type f -print0 \
  | sort -z \
  | while IFS= read -r -d '' rel
    do
      rel=${rel#./}
      for ignore in "${IGNORE_RELS[@]}"
      do
        case "$rel" in
          "$ignore"|"$ignore"*)
            continue 2
          ;;
        esac
      done
      local fs_path path hash_line hash
      fs_path="$root/$rel"
      path=/$rel

      if hash_line=$(sha256sum "$fs_path" 2>/dev/null)
      then
        hash=${hash_line%% *}
        printf '%s  %s\n' "$hash" "$path"
      else
        log_err "failed to hash $path (need root?)"
        exit 1
      fi
    done
}

require_root() {
  if [[ $(id -u) -ne 0 ]]
  then
    log_err "live root measurement needs root privileges (rerun with sudo?)"
    exit 1
  fi
}

measure_live_root() {
  log_info "mode=live-root hashing / (excluding dev/proc/sys/run/tmp)"
  require_root
  hash_tree /
}

measure_initrd_image() {
  local initrd_path="$1"

  local initrd_src
  initrd_src=$(resolve_initrd_path "$initrd_path")
  if [[ ! -f "$initrd_src" && "$initrd_path" == "/run/current-system/initrd" && -f /run/booted-system/initrd ]]
  then
    log_warn "initrd not found at $initrd_src, falling back to /run/booted-system/initrd"
    initrd_src=/run/booted-system/initrd
  fi
  if [[ ! -f "$initrd_src" ]]
  then
    log_err "initrd not found: $initrd_src"
    return 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  add_exit_trap "rm -rf '$tmpdir'"

  local decompress_cmd

  if command -v zstd &>/dev/null && zstd -t "$initrd_src" &>/dev/null
  then
    decompress_cmd="zstd -dc"
  elif command -v gzip &>/dev/null && gzip -t "$initrd_src" &>/dev/null
  then
    decompress_cmd="gzip -dc"
  else
    decompress_cmd="cat"
  fi

  log_info "mode=initrd-image source=$initrd_src unpack_dir=$tmpdir"

  cd "$tmpdir"
  $decompress_cmd "$initrd_src" | cpio -idmu

  hash_tree "$tmpdir"
  rm -rf "$tmpdir"
}

measure_remote_live_root() {
  local host=$1
  local ssh_user=$2
  local remote_env=()
  if [[ -n "$REMOTE_PATH_PREFIX" ]]
  then
    remote_env=(env "PATH=${REMOTE_PATH_PREFIX}:\$PATH")
  fi

  log_info "remote host=$host user=$ssh_user mode=live-root"

  ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" "${remote_env[@]}" bash -s << 'EOF'
set -eu

hash_tree() {
  local root
  root=$1

  local ignore_rels=(
    "etc/machine-id"
    "var/empty/.bash_history"
    "etc/ssh/initrd/ssh_host_"
    ".initrd-secrets/etc/ssh/initrd/ssh_host_"
  )

  cd "$root"

  find . -xdev \
    \( -path ./dev -o -path ./proc -o -path ./sys -o -path ./run -o -path ./tmp \) -prune -o \
    -type f -print0 \
  | sort -z \
  | while IFS= read -r -d '' rel
    do
      rel=${rel#./}
      for ignore in "${ignore_rels[@]}"
      do
        case "$rel" in
          "$ignore"|"$ignore"*)
            continue 2
          ;;
        esac
      done
      local path hash_line hash
      path=/$rel

      if hash_line=$(sha256sum "$path" 2>/dev/null)
      then
        set -- $hash_line
        hash=$1
        printf '%s  %s\n' "$hash" "$path"
      else
        echo "error: failed to hash $path" >&2
        exit 1
      fi
    done
}

  if [ "$(id -u)" -ne 0 ]
  then
    echo "error: live root measurement needs root privileges (rerun with sudo or inside initrd)" >&2
    exit 1
  fi

hash_tree /
EOF
}

measure_remote_initrd_image() {
  local host initrd_path ssh_user
  host=$1
  initrd_path=$2
  ssh_user=$3
  local remote_env=()
  if [[ -n "$REMOTE_PATH_PREFIX" ]]
  then
    remote_env=(env "PATH=${REMOTE_PATH_PREFIX}:\$PATH")
  fi

  log_info "remote host=$host user=$ssh_user mode=initrd-image path=$initrd_path"

  ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" "${remote_env[@]}" sh -s "$initrd_path" << 'EOF'
set -eu

resolve_initrd_path() {
  local path resolved
  path=$1

  if resolved=$(readlink -f "$path" 2>/dev/null)
  then
    printf '%s\n' "$resolved"
    return
  fi

  if resolved=$(realpath "$path" 2>/dev/null)
  then
    printf '%s\n' "$resolved"
    return
  fi

  printf '%s\n' "$path"
}

hash_tree() {
  local root
  root=$1

  local ignore_rels=(
    "etc/machine-id"
    "var/empty/.bash_history"
    "etc/ssh/initrd/ssh_host_"
    ".initrd-secrets/etc/ssh/initrd/ssh_host_"
  )

  cd "$root"

  find . -xdev \
    \( -path ./dev -o -path ./proc -o -path ./sys -o -path ./run -o -path ./tmp \) -prune -o \
    -type f -print0 \
  | sort -z \
  | while IFS= read -r -d '' rel
    do
      rel=${rel#./}
      for ignore in "${ignore_rels[@]}"
      do
        case "$rel" in
          "$ignore"|"$ignore"*)
            continue 2
          ;;
        esac
      done
      local fs_path path hash_line hash
      fs_path="$root/$rel"
      path=/$rel

      if hash_line=$(sha256sum "$fs_path" 2>/dev/null)
      then
        set -- $hash_line
        hash=$1
        printf '%s  %s\n' "$hash" "$path"
      else
        echo "error: failed to hash $path" >&2
        exit 1
      fi
    done
}

INITRD_PATH=$1
INITRD_SRC=$(resolve_initrd_path "$INITRD_PATH")
if [ ! -f "$INITRD_SRC" ] && [ "$INITRD_PATH" = "/run/current-system/initrd" ] && [ -f /run/booted-system/initrd ]; then
  echo "warn: initrd not found at $INITRD_SRC, falling back to /run/booted-system/initrd" >&2
  INITRD_SRC=/run/booted-system/initrd
fi
if [ ! -f "$INITRD_SRC" ]; then
  echo "error: initrd not found: $INITRD_SRC" >&2
  exit 1
fi
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT
DECOMPRESS_CMD=""

if command -v zstd >/dev/null 2>&1 && zstd -t "$INITRD_SRC" >/dev/null 2>&1
then
  DECOMPRESS_CMD="zstd -dc"
elif command -v gzip >/dev/null 2>&1 && gzip -t "$INITRD_SRC" >/dev/null 2>&1
then
  DECOMPRESS_CMD="gzip -dc"
else
  DECOMPRESS_CMD="cat"
fi

cd "$TMPDIR"
$DECOMPRESS_CMD "$INITRD_SRC" | cpio -idmu

hash_tree "$TMPDIR"

rm -rf "$TMPDIR"
EOF
}

sort_and_filter() {
  local file
  file=$1
  sort "$file"
}

diff_hashes() {
  local file1 file2
  file1=$1
  file2=$2

  if [[ ! -f "$file1" ]]
  then
    log_err "file not found: $file1"
    exit 1
  fi

  if [[ ! -f "$file2" ]]
  then
    log_err "file not found: $file2"
    exit 1
  fi

  log_info "diffing files"
  log_info "command: diff -u <(sort \"$file1\") <(sort \"$file2\")"
  if diff -u <(sort_and_filter "$file1") <(sort_and_filter "$file2")
  then
    log_ok "files are identical"
  fi
}

detect_remote_initrd() {
  local host ssh_user
  host=$1
  ssh_user=$2
  local remote_env=()
  if [[ -n "$REMOTE_PATH_PREFIX" ]]
  then
    remote_env=(env "PATH=${REMOTE_PATH_PREFIX}:\$PATH")
  fi

  if ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" -- 'test -e /etc/initrd-release'
  then
    log_info "remote host=$host appears to be in initrd"
    printf 'initrd\n'
  else
    log_info "remote host=$host appears to be in stage-1+rootfs"
    printf 'root\n'
  fi
}

detect_local_initrd() {
  if [[ -e /etc/initrd-release ]]
  then
    log_info "local system appears to be in initrd"
    printf 'initrd\n'
  else
    log_info "local system appears to be in stage-1+rootfs"
    printf 'root\n'
  fi
}

deploy_paranoid_bundle() {
  local host ssh_user
  host=$1
  ssh_user=$2

  local remote_uname
  remote_uname=$(ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" "uname -m")
  log_info "remote arch detected: $remote_uname"
  local nix_attr="nixpkgs#pkgsStatic.busybox"
  case "$remote_uname" in
    aarch64)
      nix_attr="nixpkgs#legacyPackages.aarch64-linux.pkgsStatic.busybox"
    ;;
    x86_64)
      nix_attr="nixpkgs#legacyPackages.x86_64-linux.pkgsStatic.busybox"
    ;;
  esac

  local remote_root="/run/initrd-checksum/bin"
  log_info "deploying busybox bundle to $host:$remote_root"
  ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" "mkdir -p '$remote_root'"

  local busybox_src
  if command -v nix &>/dev/null
  then
    log_debug "building '$nix_attr' via nix (with --fallback)"
    local build_out
    if build_out=$(nix build "$nix_attr" --fallback --print-out-paths 2>/dev/null | tail -n1)
    then
      busybox_src="$build_out/bin/busybox"
    fi
  fi

  if [[ -z "$busybox_src" || ! -x "$busybox_src" ]]
  then
    log_err "busybox nix build failed? cannot proceed"
    exit 1
  fi

  log_info "uploading busybox from $busybox_src"
  ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" "cat > '$remote_root/busybox' && chmod +x '$remote_root/busybox'" < "$busybox_src"

  # Symlink required applets to busybox (single ssh)
  local applets=(find sort sha256sum readlink realpath cpio gzip)
  log_info "linking applets: ${applets[*]}"
  ssh "${SSH_OPTS[@]}" -l "$ssh_user" "$host" "cd '$remote_root' && for a in ${applets[*]}; do ln -sf busybox \"\$a\"; done"

  REMOTE_PATH_PREFIX="$remote_root"
}

run_checksum() {
  local host initrd_path initrd_mode ssh_user diff_target mode tmpfile quiet paranoid
  host=$1
  initrd_path=$2
  initrd_mode=$3
  ssh_user=$4
  diff_target=$5
  quiet=$6
  paranoid=$7

  tmpfile=$(mktemp)
  add_exit_trap "rm -f '$tmpfile'"

  if [[ -n "$host" ]]
  then
    if [[ -n "$paranoid" ]]
    then
      deploy_paranoid_bundle "$host" "$ssh_user"
    fi

    if [[ "$initrd_mode" == "1" ]]
    then
      measure_remote_initrd_image "$host" "$initrd_path" "$ssh_user" > "$tmpfile"
    else
      mode=$(detect_remote_initrd "$host" "$ssh_user")
      if [[ "$mode" == "initrd" ]]
      then
        measure_remote_live_root "$host" "$ssh_user" > "$tmpfile"
      else
        measure_remote_initrd_image "$host" "$initrd_path" "$ssh_user" > "$tmpfile"
      fi
    fi
  else
    if [[ "$initrd_mode" == "1" ]]
    then
      measure_initrd_image "$initrd_path" > "$tmpfile"
    else
      mode=$(detect_local_initrd)
      if [[ "$mode" == "initrd" ]]
      then
        measure_live_root > "$tmpfile"
      else
        measure_initrd_image "$initrd_path" > "$tmpfile"
      fi
    fi
  fi

  if [[ -n "$quiet" ]]
  then
    log_info "quiet mode enabled; checksum output suppressed (temporary file: $tmpfile; will be removed on exit)"
  else
    cat "$tmpfile"
  fi

  if [[ -n "$diff_target" ]]
  then
    log_info "diffing checksum output against $diff_target"
    diff_hashes "$diff_target" "$tmpfile"
  fi
}

main() {
  setup_colors

  local action host initrd_mode initrd_path ssh_user diff_file1 diff_file2 checksum_diff quiet
  if [[ $# -gt 0 ]]
  then
    case "$1" in
      --help|-h)
        usage
        exit 0
      ;;
    esac
  fi

  action=${1:-checksum}
  if [[ $# -gt 0 ]]
  then
    shift
  fi

  host=""
  initrd_mode=""
  initrd_path=""
  ssh_user=root
  diff_file1=""
  diff_file2=""
  checksum_diff=""
  quiet=""
  local paranoid=""

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      --host|--hostname|-H)
        if [[ $# -lt 2 ]]
        then
          log_err "missing argument for $1"
          exit 2
        fi
        host=$2
        shift 2
      ;;
      --initrd)
        initrd_mode=1
        if [[ $# -gt 1 ]]
        then
          case "$2" in
            -*)
              :
            ;;
            *)
              initrd_path=$2
              shift
            ;;
          esac
        fi
        shift
      ;;
      --initrd=*)
        initrd_mode=1
        initrd_path=${1#--initrd=}
        shift
      ;;
      --ssh-user|--ssh-username|-l)
        if [[ $# -lt 2 ]]
        then
          log_err "missing argument for $1"
          exit 2
        fi
        ssh_user=$2
        shift 2
      ;;
      --diff)
        if [[ "$action" == "diff" ]]
        then
          if [[ -z "$diff_file1" ]]
          then
            diff_file1=$2
          elif [[ -z "$diff_file2" ]]
          then
            diff_file2=$2
          else
            log_err "too many arguments for diff"
            exit 2
          fi
          shift 2
        else
          if [[ $# -lt 2 ]]
          then
            log_err "missing argument for --diff FILE"
            exit 2
          fi
          checksum_diff=$2
          shift 2
        fi
      ;;
      --help|-h)
        usage
        exit 0
      ;;
      -q|--quiet)
        quiet=1
        shift
      ;;
      --paranoid)
        paranoid=1
        shift
      ;;
      *)
        if [[ "$action" == "diff" ]]
        then
          if [[ -z "$diff_file1" ]]
          then
            diff_file1=$1
          elif [[ -z "$diff_file2" ]]
          then
            diff_file2=$1
          else
            log_err "unexpected argument: $1"
            exit 2
          fi
          shift
        else
          log_err "unknown argument: $1"
          usage
          exit 2
        fi
      ;;
    esac
  done

  if [[ -z "$initrd_path" ]]
  then
    initrd_path=/run/current-system/initrd
  fi

  case "$action" in
    checksum|check)
      if [[ -n "$host" ]] && [[ "$host" == *@* ]]
      then
        log_err "use --ssh-user/--ssh-username/-l instead of embedding '@' in --host"
        exit 2
      fi
      run_checksum "$host" "$initrd_path" "$initrd_mode" "$ssh_user" "$checksum_diff" "$quiet" "$paranoid"
    ;;
    diff)
      if [[ -z "$diff_file1" || -z "$diff_file2" ]]
      then
        log_err "diff mode needs two files"
        exit 2
      fi
      diff_hashes "$diff_file1" "$diff_file2"
    ;;
    *)
      log_err "unknown action: $action"
      usage
      exit 2
    ;;
  esac
}

main "$@"
