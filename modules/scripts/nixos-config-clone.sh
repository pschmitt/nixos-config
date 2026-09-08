# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Bootstrap \$HOME/devel/private/pschmitt/nixos-config.git by cloning it if it
doesn't exist yet. Never touches /etc/nixos itself (that symlink is managed
declaratively via systemd-tmpfiles, see modules/nixos-config-symlink.nix).
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

  # Mirror the tmpfiles L condition (modules/nixos-config-symlink.nix): only
  # bootstrap repo_dir in the same cases where that rule would actually
  # create (or has already created) the /etc/nixos symlink. Otherwise this
  # would clone an orphan checkout that nothing ever uses on every host that
  # still has a real, populated legacy /etc/nixos.
  if [[ -e "$link" && ! -L "$link" && -n "$(ls -A "$link")" ]]
  then
    printf '%s already holds a populated checkout; not bootstrapping %s\n' "$link" "$repo_dir"
    return 0
  fi

  if [[ -d "$repo_dir/.git" ]]
  then
    printf '%s already exists, nothing to do\n' "$repo_dir"
    return 0
  fi

  printf 'Cloning nixos-config into %s\n' "$repo_dir"
  mkdir -p "$(dirname "$repo_dir")"
  git clone https://github.com/pschmitt/nixos-config "$repo_dir"
  chown -R "$user" "$home_dir/devel"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
