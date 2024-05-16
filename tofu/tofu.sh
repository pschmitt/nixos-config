#!/usr/bin/env bash

echo_info() {
  echo -e "\033[0;34mINF\033[0m $*" >&2
}

sops_decrypt() {
  local dest="${TOFU_DIR:-${PWD}}"
  local age_key
  age_key=$(ssh-to-age -private-key -i "$SSH_IDENTITY_FILE")

  unset SOPS_AGE_KEY_FILE
  # FIXME naming the file tofu.tfvars.json does not work
  # only terraform.tfvars.json works
  # https://opentofu.org/docs/language/values/variables/#variable-definitions-tfvars-files
  SOPS_AGE_KEY="$age_key" \
    sops -d "${dest}/terraform.tfvars.sops.json" \
    > "${dest}/terraform.tfvars.json"
}

cleanup() {
  if [[ -z "$KEEP_SECRETS" ]]
  then
    rm -vf "${TD_DIR:-$PWD}/terraform.tfvars.json"
  fi

  if [[ -n "$CLONE_CONFIG" ]]
  then
    echo_info "Cleaning up config in $NIXOS_CONFIG_TMP_DIR..."
    rm -rf "$NIXOS_CONFIG_TMP_DIR"
  else
    echo_info "Resetting git state in $NIXOS_CONFIG_DIR..."
    git -C "$NIXOS_CONFIG_DIR" reset --mixed &>/dev/null
  fi
}

main() {
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  NIXOS_CONFIG_DIR="${NIXOS_CONFIG_DIR:-/etc/nixos}"
  TOFU_DIR="${TOFU_DIR:-${NIXOS_CONFIG_DIR}/tofu}"
  SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-${HOME}/.ssh/id_ed25519}"

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -k|--keep-secrets|--keep-tfvars)
        KEEP_SECRETS=1
        shift
        ;;
      # -d|--dirty*)
      #   DIRTY=1
      #   shift
      #   ;;
      -c|--clone*)
        CLONE_CONFIG=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  sops_decrypt || exit 1
  # shellcheck disable=SC2155
  export AWS_ACCESS_KEY_ID=$(jq -er '.s3_access_key_id' terraform.tfvars.json)
  # shellcheck disable=SC2155
  export AWS_SECRET_ACCESS_KEY=$(jq -er '.s3_secret_access_key' terraform.tfvars.json)

  if [[ -n "$CLONE_CONFIG" ]]
  then
    echo_info "Cloning nixos config..."
    NIXOS_CONFIG_TMP_DIR=$(zhj nix::clone-config) || exit 3
    echo_info "NIXOS_CONFIG_TMP_DIR: $NIXOS_CONFIG_TMP_DIR"
    TOFU_DIR="${NIXOS_CONFIG_TMP_DIR}/tofu"
  else
    echo_info "Adding all files in $NIXOS_CONFIG_DIR to git..."
    git -C "$NIXOS_CONFIG_DIR" add --intent-to-add . &>/dev/null
  fi

  trap 'cleanup' EXIT

  tofu -chdir="${TOFU_DIR}" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
