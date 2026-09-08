# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Ensure /etc/nixos is a symlink into \$HOME/devel/private/pschmitt/nixos-config.git,
cloning that checkout first if it doesn't exist yet. A pre-existing, already
populated /etc/nixos (a legacy plain checkout, or an already-migrated
symlink) is left untouched.
EOF
}

main() {
  if [[ -n "${1:-}" ]]
  then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  local home_dir="${NIXOS_CONFIG_HOME:?NIXOS_CONFIG_HOME is not set}"
  local user="${NIXOS_CONFIG_USER:?NIXOS_CONFIG_USER is not set}"
  local repo_dir="$home_dir/devel/private/pschmitt/nixos-config.git"
  local link=/etc/nixos

  if [[ -L "$link" ]]
  then
    printf '%s is already a symlink, nothing to do\n' "$link"
    return 0
  fi

  if [[ -e "$link" && -n "$(ls -A "$link")" ]]
  then
    printf '%s already holds a populated checkout, leaving it alone\n' "$link"
    return 0
  fi

  if [[ ! -d "$repo_dir/.git" ]]
  then
    printf 'Cloning nixos-config into %s\n' "$repo_dir"
    mkdir -p "$(dirname "$repo_dir")"
    git clone https://github.com/pschmitt/nixos-config "$repo_dir"
    chown -R "$user" "$home_dir/devel"
  fi

  if [[ -d "$link" ]]
  then
    rmdir "$link"
  fi

  printf 'Linking %s -> %s\n' "$link" "$repo_dir"
  ln -s "$repo_dir" "$link"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
