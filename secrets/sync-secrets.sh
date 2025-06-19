#!/usr/bin/env bash

get_secret_value() {
  local sops_file="$1"
  local path="$2"

  sops decrypt --extract "$path" "$sops_file"
}

update_secret() {
  local sops_file="$1"
  local path="$2"
  local value="$3"

  local current_value
  current_value="$(get_secret_value "$sops_file" "$path")"

  if [[ -n $current_value && "$current_value" == "$value" ]]
  then
    echo "Secret '${path}' in '${sops_file}' is up to date" >&2
    return 0
  fi

  echo "Setting '${path}' in '${sops_file}' to '${value}'" >&2
  # NOTE value needs to be a JSON string
  sops set "$sops_file" "$path" "\"$value\""
}

update_wiit_openvpn_secret() {
  local sops_file="shared.sops.yaml"
  local path='["openvpn"]["wiit"]["password"]'
  local value

  if ! value="$(rbw get vpn.wiit.one)"
  then
    echo "Failed to retrieve the secret from Bitwarden." >&2
    return 1
  fi

  update_secret "$sops_file" "$path" "$value"
}

git_diff_sops_files() {
  local git_root
  git_root="$(git rev-parse --show-toplevel)"

  git -C "$git_root" diff --name-only HEAD | \
    grep -E 'sops' | \
    xargs --no-run-if-empty git -C "$git_root" diff HEAD --

}

main() {
  rbw sync

  update_wiit_openvpn_secret
  git_diff_sops_files
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  main "$@"
fi
