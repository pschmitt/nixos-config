#!/usr/bin/env bash

usage() {
  printf 'Usage: %s [install] ARCHIVE TRUSTED_SHA256 | restore | gc [--keep COUNT] [--dry-run]\n' "$(basename "$0")"
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

package_required_by_retained_generation() {
  local root=$1 wanted=$2 generation package
  for generation in "$root"/generations/*
  do
    [[ -d "$generation" && -r "$generation/base-packages.txt" ]] || continue
    while IFS= read -r package
    do
      [[ "$package" == "$wanted" ]] && return 0
    done < "$generation/base-packages.txt"
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
  local root=$1 dry_run=${2:-0} package simulation removal_plan
  local -a owned=() remaining=()
  [[ -f "$root/apt-owned-packages.txt" ]] || return 0
  mapfile -t owned < "$root/apt-owned-packages.txt" || return
  for package in "${owned[@]}"
  do
    if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
    then
      printf 'Invalid Termux APT package name in package metadata: %s\n' "$package" >&2
      return 1
    fi
  done
  for package in "${owned[@]}"
  do
    if package_required_by_retained_generation "$root" "$package"
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
    if [[ "$dry_run" == 1 ]]
    then
      printf 'Would remove obsolete Termux APT package: %s\n' "$package"
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

gc_generations() (
  local root=$1 keep_count=$2 dry_run=$3 index="$1/generation-index.tsv"
  local current_path current_id number id extra generation_dir ordered_index index_temp
  local plan_root package_owner_file
  local -A numbers=() used_numbers=() retained=()
  local -a removal_candidates=()

  if [[ ! -s "$index" ]]
  then
    printf 'Generation index is missing; refusing to remove generations.\n' >&2
    return 1
  fi

  current_path=$(readlink -f -- "$root/current") || return
  case "$current_path" in
    "$root"/generations/*) ;;
    *)
      printf 'Current generation points outside the managed generation directory.\n' >&2
      return 1
      ;;
  esac
  current_id=${current_path##*/}
  if [[ ! "$current_id" =~ ^[0-9a-f]{64}$ ||
        ! -d "$root/generations/$current_id" ||
        ! -f "$root/generations/$current_id/manifest.json" ||
        ! -r "$root/generations/$current_id/base-packages.txt" ]]
  then
    printf 'Current generation is incomplete; refusing garbage collection.\n' >&2
    return 1
  fi

  ordered_index=$(mktemp "$root/.gc-index.XXXXXXXX") || return
  trap 'rm -f -- "$ordered_index"; [[ -z "$plan_root" ]] || rm -rf -- "$plan_root"' EXIT
  while IFS=$'\t' read -r number id extra || [[ -n "$number$id$extra" ]]
  do
    [[ -n "$number$id$extra" ]] || continue
    if [[ ! "$number" =~ ^[1-9][0-9]*$ ||
          ! "$id" =~ ^[0-9a-f]{64}$ ||
          -n "$extra" ||
          -n "${numbers[$id]:-}" ||
          -n "${used_numbers[$number]:-}" ]]
    then
      printf 'Invalid generation index entry; refusing garbage collection.\n' >&2
      return 1
    fi
    numbers[$id]=$number
    used_numbers[$number]=1
  done < "$index"

  for id in "${!numbers[@]}"
  do
    generation_dir="$root/generations/$id"
    if [[ -L "$generation_dir" || ( -e "$generation_dir" && ! -d "$generation_dir" ) ]]
    then
      printf 'Indexed generation is not a managed directory; refusing garbage collection: %s\n' "$id" >&2
      return 1
    fi
  done

  for generation_dir in "$root"/generations/*
  do
    id=${generation_dir##*/}
    if [[ "$id" =~ ^[0-9a-f]{64}$ && -L "$generation_dir" ]]
    then
      printf 'Generation path is a symlink; refusing garbage collection: %s\n' "$id" >&2
      return 1
    fi
    [[ -d "$generation_dir" && ! -L "$generation_dir" ]] || continue
    [[ "$id" =~ ^[0-9a-f]{64}$ ]] || continue
    if [[ -z "${numbers[$id]:-}" ]]
    then
      printf 'Generation is not present in the index; refusing garbage collection: %s\n' "$id" >&2
      return 1
    fi
  done

  while IFS=$'\t' read -r number id
  do
    if [[ -L "$root/generations/$id" ]]
    then
      printf 'Generation path is a symlink; refusing garbage collection: %s\n' "$id" >&2
      return 1
    fi
    [[ -d "$root/generations/$id" ]] || continue
    printf '%s\t%s\n' "$number" "$id"
  done < "$index" | LC_ALL=C sort -t $'\t' -k1,1nr > "$ordered_index" || return

  local retained_count=0
  while IFS=$'\t' read -r number id
  do
    [[ -n "$id" ]] || continue
    if (( retained_count < keep_count ))
    then
      retained[$id]=1
      ((retained_count += 1))
    fi
  done < "$ordered_index"
  retained[$current_id]=1

  while IFS=$'\t' read -r number id
  do
    [[ -n "$id" ]] || continue
    [[ -n "${retained[$id]:-}" ]] && continue
    if [[ ! -f "$root/generations/$id/manifest.json" ||
          ! -r "$root/generations/$id/base-packages.txt" ]]
    then
      printf 'Keeping incomplete generation: %s\n' "$id"
      retained[$id]=1
      continue
    fi
    removal_candidates+=("$id")
  done < "$ordered_index"

  printf 'Retaining %s generation(s), including the active generation.\n' "${#retained[@]}"
  if ((${#removal_candidates[@]} == 0))
  then
    printf 'No old generations are eligible for removal.\n'
  else
    for id in "${removal_candidates[@]}"
    do
      if [[ "$dry_run" == 1 ]]
      then
        printf 'Would remove generation %s\n' "$id"
      else
        generation_dir="$root/generations/$id"
        if ! chmod -R u+w -- "$generation_dir" || ! rm -rf -- "$generation_dir"
        then
          printf 'Keeping generation because removal failed: %s\n' "$id" >&2
          retained[$id]=1
          continue
        fi
        printf 'Removed generation %s\n' "$id"
      fi
    done
  fi

  if [[ "$dry_run" == 1 ]]
  then
    plan_root=$(mktemp -d "$root/.gc-plan.XXXXXXXX") || return
    mkdir "$plan_root/generations" || return
    for id in "${!retained[@]}"
    do
      [[ -d "$root/generations/$id" ]] || continue
      ln -s "$root/generations/$id" "$plan_root/generations/$id" || return
    done
    package_owner_file="$root/apt-owned-packages.txt"
    if [[ -f "$package_owner_file" ]]
    then
      cp -- "$package_owner_file" "$plan_root/apt-owned-packages.txt" || return
    fi
    remove_obsolete_apt_packages "$plan_root" 1
    return
  fi

  index_temp=$(mktemp "$root/.generation-index.XXXXXXXX") || return
  while IFS=$'\t' read -r number id
  do
    [[ -d "$root/generations/$id" && ! -L "$root/generations/$id" ]] || continue
    printf '%s\t%s\n' "$number" "$id"
  done < "$ordered_index" | LC_ALL=C sort -t $'\t' -k1,1n > "$index_temp" || {
    rm -f -- "$index_temp"
    return 1
  }
  mv -f -- "$index_temp" "$index" || return
  remove_obsolete_apt_packages "$root"
)

run_generation_gc() {
  local root="$HOME/.local/share/termux-native"
  local keep_count=$1 dry_run=$2
  mkdir -p "$root/generations" || return
  mkdir "$root/.lock" || {
    printf 'Another Termux-native bootstrap, activation, or garbage collection is in progress.\n' >&2
    return 1
  }
  trap cleanup_bootstrap_lock EXIT
  gc_generations "$root" "$keep_count" "$dry_run"
}

main() {
  local installer root backup temporary shell_file generation archive checksum
  local keep_count=3 dry_run=0

  if [[ "${1:-}" == gc ]]
  then
    shift
    while (($#))
    do
      case "$1" in
        --keep)
          if (($# < 2))
          then
            usage >&2
            return 2
          fi
          keep_count=$2
          shift 2
          ;;
        --dry-run)
          dry_run=1
          shift
          ;;
        -h | --help)
          usage
          return 0
          ;;
        *)
          usage >&2
          return 2
          ;;
      esac
    done
    if [[ ! "$keep_count" =~ ^[1-9][0-9]*$ ]] || ((keep_count > 1000))
    then
      printf 'Generation retention must be between 1 and 1000.\n' >&2
      return 2
    fi
    run_generation_gc "$keep_count" "$dry_run"
    return
  fi

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
  remove_obsolete_apt_packages "$root" || return
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
