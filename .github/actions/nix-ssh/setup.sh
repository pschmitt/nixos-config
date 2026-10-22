#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s (requires SSH_PRIVATE_KEY and SSH_HOSTS)\n' "$(basename "$0")"
}

main() {
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]
  then
    usage
    return 0
  fi
  if (( $# != 0 )) || [[ -z "${SSH_PRIVATE_KEY:-}" || -z "${SSH_HOSTS:-}" ]]
  then
    usage >&2
    return 2
  fi
  umask 077
  install -d -m 0700 "$HOME/.ssh"
  printf '%s\n' "$SSH_PRIVATE_KEY" > "$HOME/.ssh/id_ed25519"
  read -r -a hosts <<< "$SSH_HOSTS"
  for host in "${hosts[@]}"
  do
    for attempt in 1 2 3
    do
      if ssh-keyscan -T 10 -H "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null
      then
        break
      fi
      if (( attempt == 3 ))
      then
        printf 'Could not obtain cache/builder SSH host keys\n' >&2
        return 1
      fi
      sleep 2
    done
  done
  # shellcheck disable=SC2024 # The input belongs to this user; only tee needs root.
  sudo tee -a /etc/ssh/ssh_known_hosts < "$HOME/.ssh/known_hosts" >/dev/null
  sudo tee /etc/ssh/ssh_config.d/99-keepalive.conf >/dev/null <<'SSHCONF'
  Host *
    ServerAliveInterval 30
    ServerAliveCountMax 10
SSHCONF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
