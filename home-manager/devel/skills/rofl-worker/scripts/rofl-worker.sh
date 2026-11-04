#!/usr/bin/env bash
# Client for ad-hoc build workers: disposable, encrypted OpenStack VMs that
# the nixbot host creates on request (`rofl-worker` there). This script runs
# it over SSH, pins each worker's SSH host key locally and wraps ssh, rsync
# and Nix builder use. See ../SKILL.md.

CONTROL_HOST="${ROFL_WORKER_HOST:-rofl-14}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rofl-worker"
KNOWN_HOSTS="${STATE_DIR}/known_hosts"

usage() {
  cat <<EOF
Usage: $(basename "$0") ACTION [ARGS]

Actions:
  up [--ttl 2h] [--flavor s1.xlarge] [--disk 150]
                       create a worker, wait until it is ready, print JSON
  ls                   list ad-hoc workers (JSON)
  down NAME            delete a worker
  extend NAME --ttl D  move the expiry to now + D (max 24h)
  ssh NAME [CMD...]    ssh to the worker as agent (pinned host key)
  sync NAME SRC [DEST] rsync SRC to the worker (default ~/SRC basename)
  builder NAME         print a Nix builders line for the worker

Environment: ROFL_WORKER_HOST (default rofl-14), ROFL_WORKER_KEY
(public key file, default ~/.ssh/id_ed25519.pub).
EOF
}

remote() {
  # shellcheck disable=SC2029 # arguments are meant to expand locally
  ssh -o BatchMode=yes "$CONTROL_HOST" rofl-worker "$(printf '%q ' "$@")"
}

state_file() {
  printf '%s/%s.json\n' "$STATE_DIR" "$1"
}

worker_field() {
  local name="$1" field="$2" file
  file=$(state_file "$name")
  if [[ ! -f "$file" ]]
  then
    printf 'Unknown worker %s (not created from this host?)\n' "$name" >&2
    return 1
  fi
  jq -er --arg f "$field" '.[$f]' "$file"
}

ssh_opts() {
  printf '%s\n' \
    -o "UserKnownHostsFile=${KNOWN_HOSTS}" \
    -o StrictHostKeyChecking=yes \
    -o BatchMode=yes
}

forget() {
  local name="$1" ip
  ip=$(worker_field "$name" ip 2>/dev/null) || return 0
  if [[ -f "$KNOWN_HOSTS" ]]
  then
    ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1
  fi
  rm -f "$(state_file "$name")"
}

cmd_up() {
  local key_file="${ROFL_WORKER_KEY:-$HOME/.ssh/id_ed25519.pub}" info name ip
  if [[ ! -r "$key_file" ]]
  then
    printf 'Public key %s not readable (set ROFL_WORKER_KEY)\n' "$key_file" >&2
    return 2
  fi
  mkdir -p "$STATE_DIR" || return 1
  info=$(remote up --ssh-key "$(cat "$key_file")" \
    --owner "${USER}@$(hostname)" "$@") || return 1
  name=$(jq -er .name <<< "$info") || return 1
  ip=$(jq -er .ip <<< "$info") || return 1
  printf '%s\n' "$info" > "$(state_file "$name")"
  printf '%s %s\n' "$ip" "$(jq -er .host_key <<< "$info")" >> "$KNOWN_HOSTS"
  printf '%s\n' "$info"
}

cmd_down() {
  if [[ -z "${1:-}" ]]
  then
    usage >&2
    return 2
  fi
  remote down "$1" || return 1
  forget "$1"
}

cmd_ssh() {
  local name="${1:-}" ip opts
  if [[ -z "$name" ]]
  then
    usage >&2
    return 2
  fi
  shift
  ip=$(worker_field "$name" ip) || return 1
  mapfile -t opts < <(ssh_opts)
  # shellcheck disable=SC2029 # the command is the caller's, run as given
  ssh "${opts[@]}" "agent@${ip}" "$@"
}

cmd_sync() {
  local name="${1:-}" src="${2:-}" dest="${3:-}" ip opts
  if [[ -z "$name" || -z "$src" ]]
  then
    usage >&2
    return 2
  fi
  ip=$(worker_field "$name" ip) || return 1
  mapfile -t opts < <(ssh_opts)
  dest="${dest:-$(basename "$(realpath "$src")")}"
  rsync -a --delete --exclude target/ --exclude .direnv/ --exclude result \
    -e "ssh ${opts[*]}" "${src%/}/" "agent@${ip}:${dest}/"
}

cmd_builder() {
  local name="${1:-}" ip key
  if [[ -z "$name" ]]
  then
    usage >&2
    return 2
  fi
  ip=$(worker_field "$name" ip) || return 1
  key=$(worker_field "$name" host_key | base64 -w0) || return 1
  printf 'ssh-ng://agent@%s x86_64-linux - 16 1 nixos-test,benchmark,big-parallel,kvm - %s\n' \
    "$ip" "$key"
}

main() {
  local action="${1:-}"
  case "$action" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      usage >&2
      return 2
      ;;
  esac
  shift
  case "$action" in
    up)
      cmd_up "$@"
      ;;
    ls)
      remote ls
      ;;
    down)
      cmd_down "$@"
      ;;
    extend)
      remote extend "$@"
      ;;
    ssh)
      cmd_ssh "$@"
      ;;
    sync)
      cmd_sync "$@"
      ;;
    builder)
      cmd_builder "$@"
      ;;
    *)
      printf 'Unknown action: %s\n' "$action" >&2
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
