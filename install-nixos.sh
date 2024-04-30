#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [--age-file AGE_FILE] [--ssh-target root@nixos] TARGET_HOST"
}

decrypt() {
  local secret_file="$1"
  local identity_file="${2:-${AGE_IDENTITY_FILE:-${HOME}/.ssh/id_ed25519}}"

  local secret
  if ! secret=$(age --decrypt --identity "$identity_file" "$secret_file")
  then
    echo "Error: Failed to decrypt $secret_file" >&2
    return 1
  fi

  echo -n "$secret"
}

decrypt-ssh-host-keys() {
  local target_host="$1"
  local extra_files_dir="$2"

  local dest="${extra_files_dir}/etc/ssh"
  mkdir -p "$dest"

  local file key_type secret_file
  for key_type in rsa ed25519
  do
    file="ssh_host_${key_type}_key"
    secret_file="./secrets/${target_host}/${file}"
    decrypt "${secret_file}.age" > "${dest}/${file}"
    decrypt "${secret_file}.pub.age" > "${dest}/${file}.pub"
  done
}

decrypt-luks-passphrase() {
  local target_host="$1"
  local secret_file="./secrets/${target_host}/luks-passphrase-data.age"
  decrypt "$secret_file"
}

install-host() {
  local target_host="$1"
  local ssh_target="$2"
  local luks_passphrase_file="$3"
  local extra_files_dir="$4"
  shift 4

  # TODO We could try to determine the remote host's luks passphrase file
  # from the disko config instead of hardcoding it to /tmp/disk-1.key
  # nix run github:nix-community/nixos-anywhere -- \
  nixos-anywhere \
    --flake ".#${target_host}" \
    --disk-encryption-keys /tmp/disk-1.key "$luks_passphrase_file" \
    --extra-files "$extra_files_dir" \
    "$@" \
    "$ssh_target"
}

main() {
  AGE_IDENTITY_FILE="${HOME}/.ssh/id_ed25519"
  local ssh_target="root@nixos"

  while [[ -n "$*" ]]
  do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --age-file|--age-identity-file|--agefile|-a)
        AGE_IDENTITY_FILE="$2"
        shift 2
        ;;
      --ssh-target|--hostname)
        ssh_target="$2"
        shift 2
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

  shift

  local tmpdir extra_files_dir
  tmpdir="$(mktemp -d)"

  # shellcheck disable=SC2064
  trap "rm -rfv '$tmpdir'" EXIT

  extra_files_dir="$tmpdir/extra-files"
  mkdir -p "$extra_files_dir"

  local luks_passphrase_file="${tmpdir}/luks-passphrase"
  decrypt-luks-passphrase "$target_host" > "$luks_passphrase_file"
  decrypt-ssh-host-keys "$target_host" "$extra_files_dir"

  tree "$tmpdir"

  install-host \
    "$target_host" \
    "$ssh_target" \
    "$luks_passphrase_file" \
    "$extra_files_dir" \
    "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
  main "$@"
fi
