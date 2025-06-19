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

  echo "Updating '${path}' in '${sops_file}' to '${value}'" >&2
  # NOTE value needs to be a JSON string
  sops set "$sops_file" "$path" "\"$value\""
}

sync_bw_secret() {
  local sops_file="$1"
  local path="$2"
  local bw_item="$3"

  if ! value="$(rbw get "$bw_item")"
  then
    echo "Failed to retrieve the secret '$bw_item' from Bitwarden." >&2
    return 1
  fi

  update_secret "$sops_file" "$path" "$value"
}

update_wiit_openvpn_secret() {
  local sops_file="shared.sops.yaml"
  local path='["openvpn"]["wiit"]["password"]'
  local bw_item="vpn.wiit.one"

  sync_bw_secret "$sops_file" "$path" "$bw_item"
}

# FIXME Artifactory secret is not in Bitwarden yet
update_artifactory_secret() {
  local sops_file="shared.sops.yaml"
  local path='["artifactory"]["password"]'
  local bw_item="JFrog Artifactory"

  sync_bw_secret "$sops_file" "$path" "$bw_item"
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
  # update_artifactory_secret
  git_diff_sops_files
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  main "$@"
fi
