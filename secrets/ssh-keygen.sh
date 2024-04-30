#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [--force] TARGET_HOST"
}

main() {
  local force="${FORCE:-}"

  while [[ -n "$*" ]]
  do
    case "$1" in
      -f|--force)
        force=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  local target_host="$1"

  if [[ -z "$target_host" ]]
  then
    usage
    exit 0
  fi

  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  local key_type
  local secret_file
  local tmpfile

  for key_type in rsa ed25519
  do
    tmpfile="$(mktemp --dry-run)"
    secret_file="${target_host}/ssh_host_${key_type}_key"
    if [[ -e "$secret_file" ]] && [[ -z "$force" ]]
    then
      {
        echo "Warning: $secret_file already exists. Aborting."
        echo "Use --force to override"
      } >&2
      exit 1
    fi

    ssh-keygen -t "$key_type" -N "" -C "root@${target_host}" -f "$tmpfile"

    agenix -e "${secret_file}.age" <"$tmpfile"
    agenix -e "${secret_file}.pub.age" <"${tmpfile}.pub"
    rm -f "$tmpfile" "${tmpfile}.pub"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
