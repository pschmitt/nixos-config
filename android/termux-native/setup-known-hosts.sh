#!/usr/bin/env bash

set -euo pipefail

managed_marker='# Managed by nixpp. Do not edit.'
transaction_dir=''
known_hosts_tmp=''
config_tmp=''

cleanup() {
  [[ -z "$known_hosts_tmp" ]] || rm -f -- "$known_hosts_tmp"
  [[ -z "$config_tmp" ]] || rm -f -- "$config_tmp"
  [[ -z "$transaction_dir" ]] || rm -rf -- "$transaction_dir"
}

trap cleanup EXIT

setup_known_hosts() {
  local generation=${1:?generation path is required}
  local payload="$generation/home/.local/share/termux-native/ssh-known-hosts.sops.yaml"
  local ssh_dir="$PREFIX/etc/ssh"
  local known_hosts_dir="$ssh_dir/ssh_known_hosts.d"
  local config_dir="$ssh_dir/ssh_config.d"
  local runtime_generation=${TERMUX_GENERATION:-$generation}
  local known_hosts_file="$known_hosts_dir/nixpp"
  local config_file="$config_dir/nixpp.conf"
  local age_key file first_host

  [[ -f "$payload" ]] || return 0
  [[ -r "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]] || {
    printf 'Missing Termux SSH host identity; cannot decrypt known-hosts payload.\n' >&2
    return 1
  }

  mkdir -p "$known_hosts_dir" "$config_dir" "$PREFIX/tmp" || return
  for file in "$known_hosts_file" "$config_file"
  do
    if [[ -e "$file" ]] && [[ "$(head -n 1 "$file")" != "$managed_marker" ]]
    then
      printf 'Refusing to replace unmanaged SSH configuration: %s\n' "$file" >&2
      return 1
    fi
  done

  transaction_dir=$(mktemp -d "$PREFIX/tmp/nixpp-known-hosts.XXXXXXXX") || return
  known_hosts_tmp=$(mktemp "$known_hosts_dir/.nixpp.XXXXXXXX") || return
  config_tmp=$(mktemp "$config_dir/.nixpp.XXXXXXXX") || return
  age_key=$("$runtime_generation/bin/ssh-to-age" --private-key -i "$PREFIX/etc/ssh/ssh_host_ed25519_key") || return
  if ! SOPS_AGE_KEY="$age_key" "$runtime_generation/bin/sops" --decrypt --output-type json "$payload" 2>/dev/null |
    "$PREFIX/bin/jq" -er '.known_hosts | select(type == "string" and length > 0)' > "$transaction_dir/known_hosts"
  then
    unset age_key
    printf 'Could not decrypt the Termux known-hosts payload.\n' >&2
    return 1
  fi
  unset age_key

  first_host=$(awk 'NF >= 3 && $1 !~ /^#/ { print $1; exit }' "$transaction_dir/known_hosts") || return
  first_host=${first_host%%,*}
  if [[ -z "$first_host" ]] || ! "$PREFIX/bin/ssh-keygen" -F "$first_host" -f "$transaction_dir/known_hosts" >/dev/null
  then
    printf 'Decrypted known-hosts payload has no valid OpenSSH entries.\n' >&2
    return 1
  fi

  {
    printf '%s\n' "$managed_marker"
    cat "$transaction_dir/known_hosts"
  } > "$known_hosts_tmp" || return
  {
    printf '%s\n' "$managed_marker"
    printf 'GlobalKnownHostsFile %s/ssh_known_hosts %s/ssh_known_hosts2 %s\n' \
      "$ssh_dir" "$ssh_dir" "$known_hosts_file"
  } > "$config_tmp" || return
  chmod 600 "$known_hosts_tmp" || return
  chmod 644 "$config_tmp" || return

  if [[ -e "$known_hosts_file" ]]
  then
    cp -p "$known_hosts_file" "$transaction_dir/known_hosts.previous" || return
  fi
  if [[ -e "$config_file" ]]
  then
    cp -p "$config_file" "$transaction_dir/config.previous" || return
  fi
  if ! mv -f -- "$known_hosts_tmp" "$known_hosts_file"
  then
    printf 'Could not install managed known-hosts file.\n' >&2
    return 1
  fi
  if ! mv -f -- "$config_tmp" "$config_file"
  then
    if [[ -f "$transaction_dir/known_hosts.previous" ]]
    then
      cp -p "$transaction_dir/known_hosts.previous" "$known_hosts_file"
    else
      rm -f -- "$known_hosts_file"
    fi
    printf 'Could not install managed SSH config drop-in.\n' >&2
    return 1
  fi

  printf 'Installed nixpp managed SSH known-hosts entries.\n'
}

main() {
  if (($# != 1))
  then
    printf 'Usage: %s GENERATION_PATH\n' "$(basename "$0")" >&2
    return 2
  fi
  setup_known_hosts "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
