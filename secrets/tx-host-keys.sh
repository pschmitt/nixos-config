#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--user USER] [--ssh-opts OPTS] [--no-backup] [--no-restart] [--dry-run] TARGET_HOST"
}

echo_info() {
  echo -e "\e[1m\e[34mINF\e[0m $*" >&2
}

echo_success() {
  echo -e "\e[1m\e[32mOK\e[0m $*" >&2
}

echo_warning() {
  [[ -n "$NO_WARNING" ]] && return 0
  echo -e "\e[1m\e[33mWRN\e[0m $*" >&2
}

echo_error() {
  echo -e "\e[1m\e[31mERR\e[0m $*" >&2
}

sops_extract() {
  local host="$1" type="$2" key="$3"

  sops --decrypt --extract '["ssh"]["host_keys"]["'"${type}"'"]["'"${key}"'"]' \
    "./hosts/${host}/secrets.sops.yaml"
}

privkey() {
  local host="$1" type="$2"
  sops_extract "$host" "$type" "privkey"
}

pubkey() {
  local host="$1" type="$2"
  sops_extract "$host" "$type" "pubkey"
}

_ssh() {
  # shellcheck disable=SC2086,SC2029
<<<<<<< HEAD
  ssh ${SSH_OPTS:-} "${SSH_USER}@${TARGET_HOST}" "$@"
=======
  ssh \
    -o ControlMaster=no \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    ${SSH_OPTS:-} \
    "${SSH_USER}@${TARGET_HOST}" \
    "$@"
>>>>>>> rpi-wip
}

backup_existing_host_keys() {
  if [[ -n "${NO_BACKUP:-}" ]]
  then
    echo_info "Skipping backup of existing host keys (--no-backup)"
    return 0
  fi

  local type="$1"

  local path_priv="/etc/ssh/ssh_host_${type}_key"
  local path_pub="/etc/ssh/ssh_host_${type}_key.pub"

  local now
  now="$(date +%s)"

  _ssh "
    set -e
    if [[ -f '${path_priv}' ]]
    then
      ${SUDO} mv -v '${path_priv}' '${path_priv}.bak-${now}'
    fi
    if [[ -f '${path_pub}' ]]
    then
      ${SUDO} mv -v '${path_pub}' '${path_pub}.bak-${now}'
    fi
  "
}

remote_md5sum() {
  local fpath="$1"
  _ssh "${SUDO} cat '$fpath'" | md5sum | awk '{ print $1 }'
}

keys_already_installed() {
  local type="$1" priv="$2" pub="$3"

  local want_priv want_pub have_priv have_pub

  # calculate local desired md5
  want_priv="$(printf '%s\n' "$priv" | md5sum | awk '{print $1}')"
  want_pub="$(printf '%s\n' "$pub"  | md5sum | awk '{print $1}')"

  # get remote md5s
  local path_priv="/etc/ssh/ssh_host_${type}_key"
  local path_pub="/etc/ssh/ssh_host_${type}_key.pub"
  have_priv="$(remote_md5sum "$path_priv")"
  have_pub="$(remote_md5sum "$path_pub")"

  if [[ "$want_priv" == "$have_priv" && "$want_pub" == "$have_pub" && -n "$have_priv" && -n "$have_pub" ]]
  then
    return 0  # already installed
  fi

  echo_info "Host ${type} keys differ (or missing) on ${TARGET_HOST}"
  echo_info "want_priv: $want_priv"
  echo_info "have_priv: $have_priv"
  echo_info "want_pub:  $want_pub"
  echo_info "have_pub:  $have_pub"
  return 1
}

install_host_keys() {
  local type="$1" priv="$2" pub="$3"

  if [[ -z "$priv" || -z "$pub" ]]
  then
    echo_info "Skipping ${type}: missing key material"
    return 0
  fi

  if keys_already_installed "$type" "$priv" "$pub"
  then
    echo_success "${type} keys already up to date on ${TARGET_HOST}"
    return 0
  fi

  if [[ -n "${DRY_RUN:-}" ]]
  then
    echo_info "[DRY-RUN] Would install ${type} keys to ${TARGET_HOST}"
    return 0
  fi

  echo_info "Installing ${type} keys on ${TARGET_HOST}"

  backup_existing_host_keys "$type"

  # Ensure dir exists
  _ssh "${SUDO} install -d -m 0755 /etc/ssh"

  # Private key (strict perms)
  # Use sudo sh -c with redirection so file is created with umask 077
  # Send key via STDIN to avoid args/ps leaks
  _ssh "${SUDO} sh -c '
    umask 077 && cat > /etc/ssh/ssh_host_${type}_key.tmp && \
    mv /etc/ssh/ssh_host_${type}_key.tmp /etc/ssh/ssh_host_${type}_key && \
    chown root:root /etc/ssh/ssh_host_${type}_key && \
    chmod 600 /etc/ssh/ssh_host_${type}_key'
  " <<< "$priv"

  # Public key (world-readable)
  _ssh "${SUDO} tee /etc/ssh/ssh_host_${type}_key.pub >/dev/null" <<< "$pub"
  _ssh "${SUDO} chown root:root /etc/ssh/ssh_host_${type}_key.pub && chmod 644 /etc/ssh/ssh_host_${type}_key.pub"
}

restart_sshd() {
  if [[ -n "${NO_RESTART:-}" ]]
  then
    echo_info "Not restarting sshd (--no-restart)"
    return 0
  fi

  if [[ -n "${DRY_RUN:-}" ]]
  then
    echo_info "[DRY-RUN] Would restart sshd"
    return 0
  fi

  echo_info "Restarting sshd"
  _ssh "
    ${SUDO} systemctl restart sshd
    ${SUDO} systemctl is-active sshd
  "
}

main() {
  set -euo pipefail
  # go to the root of the repo
  cd "$(cd "$(dirname "$0")/.." >/dev/null 2>&1; pwd -P)" || exit 9

  SSH_USER="${SSH_USER:-root}"
  SSH_OPTS="${SSH_OPTS:-}"
  NO_RESTART="${NO_RESTART:-}"
  NO_BACKUP="${NO_BACKUP:-}"
  DRY_RUN="${DRY_RUN:-}"

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      help|h|-h|--help)
        usage
        exit 0
        ;;
      --user)
        shift
        SSH_USER="${1:-}"
        if [[ -z "$SSH_USER" ]]
        then
          echo_error "--user requires a value"
          exit 2
        fi
        ;;
      --ssh-opts)
        shift
        SSH_OPTS="${1:-}"
        ;;
      --no-backup|--yolo)
        NO_BACKUP="1"
        ;;
      --no-restart)
        NO_RESTART="1"
        ;;
      -k|--dryrun|--dry-run)
        DRY_RUN="1"
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo_error "Unknown option: $1"
        usage
        exit 2
        ;;
      *)
        break
        ;;
    esac
    shift
  done

  TARGET_HOST="${1:-}"

  if [[ -z ${TARGET_HOST} ]]
  then
    echo_error "TARGET_HOST is required"
    usage >&2
    exit 2
  fi

  if [[ "${SSH_USER}" == "root" ]]
  then
    SUDO=""
  else
    SUDO="sudo"
  fi

  # Extract keys
  local privkey_rsa pubkey_rsa privkey_ed25519 pubkey_ed25519
  privkey_ed25519="$(privkey "${TARGET_HOST}" ed25519)"
  pubkey_ed25519="$(pubkey "${TARGET_HOST}" ed25519)"
  privkey_rsa="$(privkey "${TARGET_HOST}" rsa)"
  pubkey_rsa="$(pubkey "${TARGET_HOST}" rsa)"

  if [[ -z $privkey_ed25519 ]]
  then
    echo_error "No ed25519 private key found for $TARGET_HOST"
    return 1
  fi

  if [[ -z $pubkey_ed25519 ]]
  then
    echo_error "No ed25519 public key found for $TARGET_HOST"
    return 1
  fi

  if [[ -z $privkey_rsa ]]
  then
    echo_error "No rsa private key found for $TARGET_HOST"
    return 1
  fi

  if [[ -z $pubkey_rsa ]]
  then
    echo_error "No rsa public key found for $TARGET_HOST"
    return 1
  fi

  echo_info "ED25519 Public Key: ${pubkey_ed25519}"
  echo_info "RSA Public Key: ${pubkey_rsa}"

  # Push keys
  install_host_keys "ed25519" "${privkey_ed25519}" "${pubkey_ed25519}"
  install_host_keys "rsa" "${privkey_rsa}" "${pubkey_rsa}"

  # Restart sshd if desired
  restart_sshd

  echo_info "Done."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
