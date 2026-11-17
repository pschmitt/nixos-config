#!/usr/bin/env bash

usage() {
  printf 'Usage: %s GENERATION_PATH [--switch-current ROOT]\n' "$(basename "$0")"
}

setup_sshd() (
  local generation=$1 switch_root=${2:-} ssh_dir="$PREFIX/etc/ssh"
  local config_dir="$PREFIX/etc/ssh/sshd_config.d"
  local backup_dir="$HOME/.local/share/termux-native/ssh-config-backups"
  local temporary_file='' committed=0
  local -a changed_files=() backups=()

  # shellcheck disable=SC2329
  cleanup() {
    local status=$? index backup
    [[ -z "$temporary_file" ]] || rm -f -- "$temporary_file"
    for ((index=${#changed_files[@]}-1; index>=0; index--))
    do
      backup=${backups[index]}
      if (( ! committed ))
      then
        if [[ -n "$backup" ]]
        then
          if ! mv -f -- "$backup" "${changed_files[index]}"
          then
            printf 'Could not restore %s; recovery copy retained at %s\n' "${changed_files[index]}" "$backup" >&2
            status=1
          fi
        else
          rm -f -- "${changed_files[index]}" || status=1
        fi
      elif [[ -n "$backup" ]]
      then
        rm -f -- "$backup" || status=1
      fi
    done
    return "$status"
  }
  trap cleanup EXIT

  remember_config() {
    local file=$1 backup=''
    if [[ -f "$file" ]]
    then
      backup=$(mktemp "$backup_dir/recovery.XXXXXXXX") || return
      if ! cp -p -- "$file" "$backup"
      then
        rm -f -- "$backup"
        return 1
      fi
    fi
    changed_files+=("$file")
    backups+=("$backup")
  }

  install_dropin() {
    local name=$1 marker=$2 payload=$3
    local file="$config_dir/nixpp-$name.conf" first_line=''
    if [[ ! -f "$payload" && ! -e "$file" && ! -L "$file" ]]
    then
      return 0
    fi
    if [[ -L "$file" || ( -e "$file" && ! -f "$file" ) ]]
    then
      printf 'Refusing to replace SSH configuration: %s\n' "$file" >&2
      return 1
    fi
    if [[ -f "$file" ]]
    then
      IFS= read -r first_line < "$file" || true
      if [[ "$first_line" != "$marker" ]]
      then
        if [[ ! -f "$payload" ]]
        then
          return 0
        fi
        printf 'Refusing to replace unmanaged SSH configuration: %s\n' "$file" >&2
        return 1
      fi
    fi
    if [[ ! -f "$payload" ]]
    then
      remember_config "$file" || return
      rm -f -- "$file" || return
      return 0
    fi
    temporary_file=$(mktemp "$config_dir/.nixpp-$name.XXXXXXXX") || return
    {
      printf '%s\n' "$marker"
      cat -- "$payload"
    } > "$temporary_file" || return
    chmod 644 "$temporary_file" || return
    remember_config "$file" || return
    mv -f -- "$temporary_file" "$file" || return
    temporary_file=''
  }

  local ports="$generation/home/.config/termux-native/sshd-ports.conf"
  local motd="$generation/home/.config/termux-native/sshd-motd.conf"
  local legacy="$config_dir/termuxpp-port.conf"
  local legacy_backup="$backup_dir/termuxpp-port.conf"
  local expected actual

  if [[ ! -f "$ports" && ! -f "$motd" &&
        ! -e "$config_dir/nixpp-ports.conf" && ! -L "$config_dir/nixpp-ports.conf" &&
        ! -e "$config_dir/nixpp-motd.conf" && ! -L "$config_dir/nixpp-motd.conf" ]]
  then
    if [[ -n "$switch_root" ]]
    then
      mv -Tf -- "$switch_root/.next" "$switch_root/current" || return
    fi
    return 0
  fi
  if [[ ! -x "$PREFIX/bin/sshd" || ! -f "$ssh_dir/sshd_config" ]]
  then
    printf 'Termux OpenSSH server and sshd_config are required.\n' >&2
    return 1
  fi
  mkdir -p -- "$config_dir" "$backup_dir" || return
  chmod 700 "$backup_dir" || return
  "$PREFIX/bin/sshd" -t -f "$ssh_dir/sshd_config" || return

  if [[ -f "$ports" && ( -e "$legacy" || -L "$legacy" ) ]]
  then
    if [[ -L "$legacy" || ! -f "$legacy" ]] || ! cmp -s "$legacy" <(printf 'Port 8023\n')
    then
      printf 'Refusing to migrate unknown legacy SSH configuration: %s\n' "$legacy" >&2
      return 1
    fi
    if [[ -e "$legacy_backup" || -L "$legacy_backup" ]]
    then
      if [[ -L "$legacy_backup" || ! -f "$legacy_backup" ]] || ! cmp -s "$legacy" "$legacy_backup"
      then
        printf 'Refusing to replace SSH migration backup: %s\n' "$legacy_backup" >&2
        return 1
      fi
    else
      cp -p -- "$legacy" "$legacy_backup" || return
    fi
    remember_config "$legacy" || return
    rm -f -- "$legacy" || return
  fi

  install_dropin ports '# Managed by nixpp. Do not edit.' "$ports" || return
  install_dropin motd '# Managed by nixpp: Termux SSH MOTD policy.' "$motd" || return
  "$PREFIX/bin/sshd" -t -f "$ssh_dir/sshd_config" || return
  actual=$("$PREFIX/bin/sshd" -T -f "$ssh_dir/sshd_config") || return
  if [[ -f "$ports" ]]
  then
    expected=$(awk 'tolower($1) == "port" { print $2 }' "$ports" | sort -nu) || return
    if [[ -z "$expected" || "$(awk 'tolower($1) == "port" { print $2 }' <<< "$actual" | sort -nu)" != "$expected" ]]
    then
      printf 'Effective SSH ports differ from the generation configuration.\n' >&2
      return 1
    fi
  fi
  if [[ -f "$motd" ]] && ! awk 'tolower($1) == "printmotd" && tolower($2) == "no" { found = 1 } END { exit !found }' <<< "$actual"
  then
    printf 'Effective SSH configuration does not disable the MOTD.\n' >&2
    return 1
  fi
  if [[ -n "$switch_root" ]]
  then
    mv -Tf -- "$switch_root/.next" "$switch_root/current" || return
  fi
  committed=1
  printf 'Installed nixpp SSH server policy.\n'
)

main() {
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]
  then
    usage
    return 0
  fi
  if [[ -z "${PREFIX:-}" ]] || (($# != 1 && $# != 3))
  then
    usage >&2
    printf 'A generation path and PREFIX are required.\n' >&2
    return 2
  fi
  if (($# == 3)) && [[ "$2" != --switch-current || -z "$3" ]]
  then
    usage >&2
    return 2
  fi
  setup_sshd "$1" "${3:-}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  set -euo pipefail
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
