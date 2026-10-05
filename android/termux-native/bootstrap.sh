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
      command rm -f -- "$temporary"
      return 1
    fi
  elif [[ -e "$backup/zshenv-absent" ]]
  then
    command rm -f -- "$PREFIX/etc/zshenv" || return
  else
    printf 'The saved startup backup is incomplete: %s\n' "$backup" >&2
    return 1
  fi

  command rm -f -- "$shell_file" || return
  if [[ -f "$backup/shell" ]]
  then
    mkdir -p "${shell_file%/*}" || return
    ln -s "$(<"$backup/shell")" "$shell_file" || return
  fi

  command rm -rf -- "$backup" || return
  printf 'Restored the original Termux zsh startup. Managed generations remain in %s/.local/share/termux-native.\n' "$HOME"
}

cleanup_bootstrap_lock() {
  rmdir -- "$HOME/.local/share/termux-native/.bootstrap-lock" 2>/dev/null || true
}

main() {
  local installer root backup temporary shell_file generation lock

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
  generation=$2
  mkdir -p "$root" || return
  lock="$root/.bootstrap-lock"
  if ! mkdir "$lock" 2>/dev/null
  then
    printf 'Another Termux bootstrap is already running.\n' >&2
    return 1
  fi
  trap cleanup_bootstrap_lock EXIT
  bash "$installer" install "$1" "$2" || return
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
