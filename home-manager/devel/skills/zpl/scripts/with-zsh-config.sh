#!/usr/bin/env bash

# Run a command with another ~/.config/zsh tree (e.g. the .config/zsh of a
# freshly built home-manager-files) bind-mounted over the real one, without
# switching or root: an outer user namespace maps root for the mount, an inner
# one maps back to the calling user.

usage() {
  cat <<EOF
Usage: $(basename "$0") ZSH_DIR -- COMMAND...

Example:
  cp -a /nix/store/...-home-manager-files/.config/zsh ./newzsh
  chmod -R u+w ./newzsh
  $(basename "$0") ./newzsh -- zsh -i -c exit
EOF
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac

  local dir="${1:-}"
  if [[ -z "$dir" || "${2:-}" != "--" || -z "${3:-}" ]]
  then
    usage >&2
    return 2
  fi
  shift 2

  if [[ ! -d "$dir" ]]
  then
    printf 'Not a directory: %s\n' "$dir" >&2
    return 1
  fi

  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"
  # shellcheck disable=SC2016 # expanded by the inner bash
  ZSH_CONFIG_UID="$uid" ZSH_CONFIG_GID="$gid" \
    exec unshare --user --map-root-user --mount bash -c '
      mount --bind "$1" "$2" || exit 1
      shift 2
      exec unshare --user --map-user="$ZSH_CONFIG_UID" --map-group="$ZSH_CONFIG_GID" "$@"
    ' bash "$(realpath "$dir")" "${XDG_CONFIG_HOME:-$HOME/.config}/zsh" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
