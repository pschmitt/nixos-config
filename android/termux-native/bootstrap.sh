#!/usr/bin/env bash

usage() {
  printf 'Usage: %s [install] ARCHIVE TRUSTED_SHA256 | restore\n' "$(basename "$0")"
}

restore_startup() {
  local backup="$HOME/.local/share/termux-native/bootstrap-backup"
  local temporary shell_file="$HOME/.termux/shell" managed_shell="$PREFIX/bin/zsh"

  if [[ ! -d "$backup" ]]
  then
    printf 'No saved Termux startup file was found.\n' >&2
    return 1
  fi
  if ! grep -Fq 'TERMUX_NATIVE_ZDOTDIR' "$PREFIX/etc/zshenv"
  then
    printf 'The managed zshenv has changed; refusing to overwrite it.\n' >&2
    printf 'Saved original: %s\n' "$backup" >&2
    return 1
  fi
  if [[ ! -L "$shell_file" ]] || [[ "$(readlink "$shell_file")" != "$managed_shell" ]]
  then
    printf 'The Termux login shell has changed; refusing to overwrite it.\n' >&2
    printf 'Managed shell: %s\n' "$managed_shell" >&2
    return 1
  fi
  if [[ ! -f "$backup/shell" && ! -e "$backup/shell-absent" ]]
  then
    printf 'The saved login shell backup is incomplete: %s\n' "$backup" >&2
    return 1
  fi

  if [[ -f "$backup/zshenv" ]]
  then
    temporary=$(mktemp "$PREFIX/etc/.zshenv.restore.XXXXXXXX") || return
    if ! cp -p "$backup/zshenv" "$temporary" || ! mv -f "$temporary" "$PREFIX/etc/zshenv"
    then
      rm -f -- "$temporary"
      return 1
    fi
  elif [[ -e "$backup/zshenv-absent" ]]
  then
    rm -f -- "$PREFIX/etc/zshenv" || return
  else
    printf 'The saved startup backup is incomplete: %s\n' "$backup" >&2
    return 1
  fi

  rm -f -- "$shell_file" || return
  if [[ -f "$backup/shell" ]]
  then
    mkdir -p "${shell_file%/*}" || return
    ln -s "$(<"$backup/shell")" "$shell_file" || return
  fi

  rm -rf -- "$backup" || return
  printf 'Restored the original Termux zsh startup. Managed generations remain in %s/.local/share/termux-native.\n' "$HOME"
}

cleanup_bootstrap_lock() {
  local root="$HOME/.local/share/termux-native"
  rm -f -- "$root/.next"
  rmdir -- "$root/.lock"
}

apt_package_installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == 'install ok installed' ]]
}

package_list_contains() {
  local wanted=$1 package
  shift
  for package in "$@"
  do
    [[ "$package" == "$wanted" ]] && return 0
  done
  return 1
}

write_owned_packages() {
  local root=$1 temporary
  shift
  temporary=$(mktemp "$root/.apt-owned-packages.XXXXXXXX") || return
  if (($#)); then
    printf '%s\n' "$@" | LC_ALL=C sort -u > "$temporary" || return
  else
    : > "$temporary" || return
  fi
  chmod 600 "$temporary" || return
  mv -f -- "$temporary" "$root/apt-owned-packages.txt"
}

install_apt_packages() {
  local root=$1 generation=$2 package install_status=0
  local -a desired=() owned=() missing=() updated_owned=()
  mapfile -t desired < "$root/generations/$generation/base-packages.txt" || return
  if [[ -f "$root/apt-owned-packages.txt" ]]
  then
    mapfile -t owned < "$root/apt-owned-packages.txt" || return
  fi
  for package in "${desired[@]}" "${owned[@]}"
  do
    if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
    then
      printf 'Invalid Termux APT package name in generation metadata: %s\n' "$package" >&2
      return 1
    fi
  done
  for package in "${desired[@]}"
  do
    if ! apt_package_installed "$package"
    then
      missing+=("$package")
    fi
  done
  if ((${#missing[@]})); then
    printf 'Installing missing Termux APT packages: %s\n' "${missing[*]}"
    pkg install -y "${missing[@]}" || install_status=$?
  else
    printf 'All requested Termux APT packages are already installed.\n'
  fi
  updated_owned=("${owned[@]}")
  for package in "${missing[@]}"
  do
    if apt_package_installed "$package" && ! package_list_contains "$package" "${updated_owned[@]}"
    then
      updated_owned+=("$package")
    fi
  done
  write_owned_packages "$root" "${updated_owned[@]}" || return
  (( install_status == 0 )) || return "$install_status"
}

remove_obsolete_apt_packages() {
  local root=$1 generation=$2 package simulation removal_plan
  local -a desired=() owned=() remaining=()
  [[ -f "$root/apt-owned-packages.txt" ]] || return 0
  mapfile -t desired < "$root/generations/$generation/base-packages.txt" || return
  mapfile -t owned < "$root/apt-owned-packages.txt" || return
  for package in "${desired[@]}" "${owned[@]}"
  do
    if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
    then
      printf 'Invalid Termux APT package name in package metadata: %s\n' "$package" >&2
      return 1
    fi
  done
  for package in "${owned[@]}"
  do
    if package_list_contains "$package" "${desired[@]}"
    then
      remaining+=("$package")
      continue
    fi
    if ! apt_package_installed "$package"
    then
      printf 'Previously managed APT package is already absent: %s\n' "$package"
      continue
    fi
    if ! simulation=$(apt-get -s remove -- "$package" 2>&1)
    then
      printf 'Keeping %s: APT removal simulation failed.\n' "$package" >&2
      remaining+=("$package")
      continue
    fi
    removal_plan=$(printf '%s\n' "$simulation" | awk '$1 == "Remv" { print $2 }')
    if [[ "$removal_plan" != "$package" ]]
    then
      printf 'Keeping %s: APT would remove additional packages or no package.\n' "$package"
      remaining+=("$package")
      continue
    fi
    if ! apt-get -y remove -- "$package" || apt_package_installed "$package"
    then
      printf 'Keeping ownership record for %s: APT did not remove it.\n' "$package" >&2
      remaining+=("$package")
      continue
    fi
    printf 'Removed obsolete Termux APT package: %s\n' "$package"
  done
  write_owned_packages "$root" "${remaining[@]}"
}

main() {
  local installer root backup temporary shell_file generation archive checksum

  case "${1:-}" in
    -h | --help)
      usage
      return 0
      ;;
    restore)
      if (($# != 1))
      then
        usage >&2
        return 2
      fi
      restore_startup
      return
      ;;
    install)
      shift
      ;;
  esac
  if (($# != 2))
  then
    usage >&2
    return 2
  fi

  installer="$(dirname "${BASH_SOURCE[0]}")/activate.sh"
  root="$HOME/.local/share/termux-native"
  archive=$1
  generation=$2
  if [[ ! -f "$archive" ]]
  then
    printf 'Bundle archive does not exist: %s\n' "$archive" >&2
    return 1
  fi
  mkdir -p "$root/generations" || return
  mkdir "$root/.lock" || {
    printf 'Another Termux-native bootstrap or activation is in progress.\n' >&2
    return 1
  }
  trap cleanup_bootstrap_lock EXIT

  checksum=$(sha256sum "$archive") || return
  checksum=${checksum:0:64}
  if [[ "$checksum" != "$generation" ]]
  then
    printf 'Bundle checksum mismatch; no Termux packages were changed.\n' >&2
    return 1
  fi
  if ! tar -tzf "$archive" >/dev/null
  then
    printf 'Bundle archive is invalid; no Termux packages were changed.\n' >&2
    return 1
  fi
  TERMUX_NATIVE_LOCK_HELD=1 bash "$installer" preflight "$archive" "$generation" || return
  install_apt_packages "$root" "$generation" || return
  TERMUX_NATIVE_LOCK_HELD=1 bash "$installer" install "$archive" "$generation" || return
  remove_obsolete_apt_packages "$root" "$generation" || return
  backup="$root/bootstrap-backup"
  shell_file="$HOME/.termux/shell"
  mkdir -p "$backup" || return
  if [[ ! -e "$backup/zshenv" && ! -e "$backup/zshenv-absent" ]]
  then
    if [[ -e "$PREFIX/etc/zshenv" ]]
    then
      cp -p "$PREFIX/etc/zshenv" "$backup/zshenv" || return
    else
      touch "$backup/zshenv-absent" || return
    fi
  fi
  if [[ ! -e "$backup/shell" && ! -e "$backup/shell-absent" ]]
  then
    if [[ -L "$shell_file" ]]
    then
      readlink "$shell_file" > "$backup/shell" || return
    elif [[ -e "$shell_file" ]]
    then
      printf 'Refusing to replace a non-symlink Termux login shell: %s\n' "$shell_file" >&2
      return 1
    else
      touch "$backup/shell-absent" || return
    fi
  fi
  temporary=$(mktemp "$PREFIX/etc/.native-zshenv.XXXXXXXX") || return
  cp "$root/generations/$generation/zshenv" "$temporary" || return
  chmod 644 "$temporary" || return
  mv -f "$temporary" "$PREFIX/etc/zshenv" || return
  chsh -s zsh || return
  printf 'Termux now starts the managed Zsh shell. Original shell and zshenv: %s\n' "$backup"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
