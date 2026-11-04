#!/usr/bin/env bash
# Client for ad-hoc build workers: disposable, encrypted OpenStack VMs that
# the control host creates on request (`rworker` there). This script runs
# it over SSH, pins each worker's SSH host key locally and wraps ssh, rsync
# and Nix builder use. See ../SKILL.md.

CONTROL_HOST="${RWORKER_HOST:-rofl-10}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rworker"
KNOWN_HOSTS="${STATE_DIR}/known_hosts"

usage() {
  cat <<EOF
Usage: $(basename "$0") ACTION [ARGS]

Actions:
  up [--ttl 2h] [--flavor s1.xlarge] [--disk 150]
                       create a worker, wait until it is ready, print JSON
  ls [-a|--all] [-o json]
                       list ad-hoc workers (--all adds nixbot's pool)
  down NAME            delete a worker
  extend NAME --ttl D  move the expiry to now + D (max 24h)
  ssh NAME [CMD...]    ssh to the worker as agent (pinned host key)
  sync NAME SRC [DEST] rsync SRC to the worker (default ~/SRC basename)
  builder NAME         print a Nix builders line for the worker

Environment: RWORKER_HOST (default rofl-10), RWORKER_KEY
(public key file, default ~/.ssh/id_ed25519.pub).
EOF
}

remote() {
  # shellcheck disable=SC2029 # arguments are meant to expand locally
  ssh -o BatchMode=yes "$CONTROL_HOST" rworker "$(printf '%q ' "$@")"
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
    ssh-keygen -R "$ip" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
  fi
  rm -f "$(state_file "$name")"
}

cmd_up() {
  local key_file="${RWORKER_KEY:-$HOME/.ssh/id_ed25519.pub}" info name ip
  if [[ ! -r "$key_file" ]]
  then
    printf 'Public key %s not readable (set RWORKER_KEY)\n' "$key_file" >&2
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

# kubectl-style table from `ls` JSON, colored like kubecolor on a terminal.
render_table() {
  local rows
  rows=$(jq -r --argjson now "$(date +%s)" '
    def dur(s):
      if s < 0 then "expired"
      elif s < 3600 then "\(s / 60 | floor)m"
      elif s < 86400 then "\(s / 3600 | floor)h\(s % 3600 / 60 | floor)m"
      else "\(s / 86400 | floor)d\(s % 86400 / 3600 | floor)h" end;
    def created: .created_at // "" | sub("\\.[0-9]+"; "") | sub("(?<z>Z?)$"; "Z")
      | if . == "Z" then null else (try fromdateiso8601 catch null) end;
    ["NAME", "KIND", "STATUS", "FLAVOR", "IP", "OWNER", "EXPIRES", "AGE"],
    (.[] | [
      .name, .kind, .status, (.flavor // "-"), (.ip // "<none>"),
      (if (.owner // "") == "" then "-" else .owner end),
      (if (.expires_at // 0) > 0 then dur(.expires_at - $now) else "-" end),
      (created as $c | if $c then dur($now - $c) else "-" end)
    ]) | @tsv') || return 1

  if [[ $(wc -l <<< "$rows") -le 1 ]]
  then
    printf 'No workers found.\n'
    return 0
  fi

  rows=$(column -t -s $'\t' <<< "$rows") || return 1
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]
  then
    local bold=$'\e[1m' green=$'\e[32m' yellow=$'\e[33m' red=$'\e[31m'
    local cyan=$'\e[36m' reset=$'\e[0m'
    sed -E \
      -e "1s/.*/${bold}&${reset}/" \
      -e "2,\$s/ (ACTIVE) / ${green}\1${reset} /" \
      -e "2,\$s/ (BUILD|REBUILD|RESIZE) / ${yellow}\1${reset} /" \
      -e "2,\$s/ (ERROR|SHUTOFF|DELETED) / ${red}\1${reset} /" \
      -e "2,\$s/ (expired) / ${red}\1${reset} /" \
      -e "2,\$s/ ([0-9]+m) ( +[0-9]+[mhd])/ ${yellow}\1${reset}\2/" \
      -e "2,\$s/^([^ ]+)/${cyan}\1${reset}/" \
      <<< "$rows"
  else
    printf '%s\n' "$rows"
  fi
}

cmd_ls() {
  local json="" args=()
  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -a|--all)
        args+=(--all)
        ;;
      -o)
        shift
        if [[ "${1:-}" != json ]]
        then
          printf 'Only -o json is supported\n' >&2
          return 2
        fi
        json=1
        ;;
      --json|-ojson)
        json=1
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  local out
  out=$(remote ls "${args[@]}") || return 1
  if [[ -n "$json" ]]
  then
    printf '%s\n' "$out"
    return 0
  fi
  render_table <<< "$out"
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
      cmd_ls "$@"
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
