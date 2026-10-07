#!/usr/bin/env bash

set -Eeuo pipefail

main() {
  local packages_blob="$1"
  local dpkg_arch cache_arch rc service
  local -a configured_packages=()

  dpkg_arch=$(dpkg --print-architecture)
  case "$dpkg_arch" in
    aarch64|arm64)
      cache_arch=aarch64
      ;;
    amd64|x86_64)
      cache_arch=x86_64
      ;;
    *)
      printf 'Unsupported Termux architecture: %s\n' "$dpkg_arch" >&2
      return 1
      ;;
  esac
  if [[ "$cache_arch" != aarch64 && "${TERMUX_CACHE_ALLOW_NON_AARCH64:-}" != 1 ]]
  then
    printf 'Expected an AArch64 Termux environment\n' >&2
    return 1
  fi
  if [[ ! "$packages_blob" =~ ^[[:xdigit:]]{40,64}$ ]]
  then
    printf 'Invalid Termux package-list revision\n' >&2
    return 2
  fi

  export TMPDIR="$PREFIX/tmp/apt-prefix-build"
  mkdir -p "$TMPDIR" /output

  apt_step() {
    local log_name="$1"
    shift
    if "$@" >"$TMPDIR/$log_name" 2>&1
    then
      return 0
    else
      rc=$?
      cp "$TMPDIR/$log_name" "/output/$log_name"
      printf 'Termux package command failed (%s); log retained on builder: %s\n' "$rc" "$log_name" >&2
      tail -n 80 "$TMPDIR/$log_name" >&2
      return "$rc"
    fi
  }

  apt_step apt-update.log apt update
  apt_step apt-upgrade.log apt full-upgrade -y
  apt_step apt-repos.log apt install -y root-repo unstable-repo yq
  apt_step apt-update-final.log apt update
  mapfile -t configured_packages < <(
    yq -r '.packages[]' /input/.config/yadm/ansible-bootstrap/roles/cli/vars/packages_termux.yml
  )
  if ((${#configured_packages[@]} == 0))
  then
    printf 'Termux package list was empty\n' >&2
    return 1
  fi
  apt_step apt-packages.log apt install -y "${configured_packages[@]}"

  apt clean >/dev/null
  rm -rf -- "$TMPDIR"
  mkdir -p "$PREFIX/tmp"

  rm -f -- "$PREFIX"/etc/ssh/ssh_host_*_key "$PREFIX"/etc/ssh/ssh_host_*_key.pub
  for service in sshd ssh-agent
  do
    local service_dir="$PREFIX/var/service/$service"
    if [[ ! -d "$service_dir" ]]
    then
      printf 'Termux service directory is missing: %s\n' "$service" >&2
      return 1
    fi
    "$PREFIX/bin/sv" down "$service_dir" >/dev/null 2>&1 || true
    : > "$service_dir/down"
  done

  tar -czf /output/termux-prefix.tar.gz \
    --exclude='usr/var/run' \
    --exclude='usr/var/log/sv' \
    --exclude='usr/var/service/*/supervise' \
    --exclude='usr/var/service/*/log/supervise' \
    -C /data/data/com.termux/files usr
  (cd /output && sha256sum termux-prefix.tar.gz > termux-prefix.tar.gz.sha256)
  printf 'format=1\narch=%s\ntermux_packages=%s\npackage_count=%s\n' \
    "$cache_arch" "$packages_blob" \
    "$(dpkg-query -W -f='${binary:Package}\n' | wc -l)" \
    > /output/termux-environment.manifest
  printf 'Built the Termux package prefix\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  if (($# != 1))
  then
    printf 'Usage: %s TERMUX_PACKAGE_LIST_GIT_OBJECT\n' "$(basename "$0")" >&2
    exit 2
  fi
  main "$1"
fi

# vim: set ft=sh et ts=2 sw=2 :
