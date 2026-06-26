# Minimal fallbacks so this file does not hard-depend on the zhj/zsh function
# library. When zhj is loaded its richer versions are already defined and win.
# (( $+functions[echo_info] )) || echo_info() { echo -e "\e[34m[INFO]\e[0m $*" >&2; }
# (( $+functions[echo_error] )) || echo_error() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

hm::profile-link() {
  local profile="$HOME/.local/state/nix/profiles/home-manager"

  if [[ ! -e "$profile" ]]
  then
    return 1
  fi

  readlink "$profile"
}

hm::profile-target() {
  local profile="$HOME/.local/state/nix/profiles/home-manager"

  if [[ ! -e "$profile" ]]
  then
    return 1
  fi

  readlink -f "$profile"
}

hm::current-generation() {
  local profile="$HOME/.local/state/nix/profiles/home-manager"
  local current_link

  if [[ ! -e "$profile" ]]
  then
    return 1
  fi

  current_link=$(readlink "$profile") || return 1

  if [[ "$current_link" != home-manager-*-link ]]
  then
    return 1
  fi

  current_link="${current_link#home-manager-}"
  current_link="${current_link%-link}"
  echo "$current_link"
}

hm::generation-link() {
  local generation="$1"
  local link="$HOME/.local/state/nix/profiles/home-manager-${generation}-link"

  if [[ -z "$generation" ]]
  then
    echo_error "Missing Home Manager generation number"
    return 2
  fi

  if [[ ! -e "$link" ]]
  then
    echo_error "Home Manager generation not found: $generation"
    return 1
  fi

  echo "$link"
}

hm::generation-target() {
  local generation="$1"
  local link

  link=$(hm::generation-link "$generation") || return $?
  readlink -f "$link"
}

hm::previous-generation() {
  local profile="$HOME/.local/state/nix/profiles/home-manager"
  local current_generation

  if [[ ! -e "$profile" ]]
  then
    return 1
  fi

  current_generation=$(hm::current-generation) || return 1

  nix-env --list-generations -p "$profile" \
    | awk -v current="$current_generation" '
        $1 < current { previous = $1 }
        END {
          if (previous == "") {
            exit 1
          }
          print previous
        }
      '
}

hm::generations() {
  local profile="$HOME/.local/state/nix/profiles/home-manager"

  if [[ ! -e "$profile" ]]
  then
    echo_error "Home Manager profile not found"
    return 1
  fi

  env PAGER=cat nix-env --list-generations -p "$profile"
}

hm::diff() {
  local old_generation="$1"
  local new_generation="$2"
  local old_target new_target

  if [[ -z "$new_generation" ]]
  then
    new_generation=$(hm::current-generation) || {
      echo_error "Unable to determine current Home Manager generation"
      return 1
    }
  fi

  if [[ -z "$old_generation" ]]
  then
    old_generation=$(hm::previous-generation) || {
      echo_error "Unable to determine previous Home Manager generation"
      return 1
    }
  fi

  old_target=$(hm::generation-target "$old_generation") || return $?
  new_target=$(hm::generation-target "$new_generation") || return $?

  echo_info "Diffing Home Manager generations $old_generation -> $new_generation"
  echo "  old target: $old_target"
  echo "  new target: $new_target"

  nvd --color always diff "$old_target" "$new_target"
}

hm::show-generation-diff() {
  local current_link="$1"
  local current_target="$2"
  local new_link="$3"
  local new_target="$4"

  if [[ -z "$current_target" || -z "$new_target" ]]
  then
    echo_error "Unable to determine Home Manager generations for diff"
    return 1
  fi

  if [[ "$current_link" == "$new_link" && "$current_target" == "$new_target" ]]
  then
    echo_info "Home Manager profile unchanged:"
    echo "  link: $new_link"
    echo "  target: $new_target"
    return 0
  fi

  if [[ "$current_target" == "$new_target" ]]
  then
    echo_info "Home Manager generation advanced, but the built result is unchanged:"
    echo "  old link: $current_link"
    echo "  new link: $new_link"
    echo "  target: $new_target"
    return 0
  fi

  echo_info "Home Manager generation changed:"
  echo "  old link: $current_link"
  echo "  new link: $new_link"
  echo "  old target: $current_target"
  echo "  new target: $new_target"

  nvd --color always diff "$current_target" "$new_target"
}

hm::rebuild() {
  local repo="$HOME/devel/private/pschmitt/nixos-config.git"
  local target_host
  local current_link current_gen new_link new_gen

  zparseopts -D -E -K -- \
    {-host,-target,-target-host}:=target_host

  target_host="${target_host[2]}"

  if [[ -z "$target_host" ]]
  then
    if [[ $# -gt 0 && "$1" != -* ]]
    then
      target_host="$1"
      shift
    else
      target_host="${HOSTNAME:-$(hostname)}"
    fi
  fi

  current_link=$(hm::profile-link) || current_link=""
  current_gen=$(hm::profile-target) || current_gen=""

  local build_parent_dir="/nix/tmp/hm-builds"
  local build_group
  build_group=$(id -gn)

  if [[ ! -d "$build_parent_dir" ]]
  then
    if ! mkdir -p "$build_parent_dir" 2>/dev/null
    then
      sudo install -d -m 0775 -o "$USER" -g "$build_group" "$build_parent_dir"
    fi
  fi

  if [[ ! -w "$build_parent_dir" ]]
  then
    sudo chown "$USER:$build_group" "$build_parent_dir"
    sudo chmod 0775 "$build_parent_dir"
  fi

  local build_dir
  if ! build_dir=$(mktemp -d -p "$build_parent_dir" "hm-build-XXXXX")
  then
    echo_error "Failed to create temporary build directory in $build_parent_dir"
    return 1
  fi

  trap 'rm -rf -- "$build_dir"' EXIT

  rsync -az \
    --delete --delete-excluded \
    --exclude '.git*' \
    --exclude 'build/' \
    --exclude 'result' \
    "$repo/" "$build_dir/"
  local rsync_rc=$?
  if [[ "$rsync_rc" -ne 0 ]]
  then
    return "$rsync_rc"
  fi

  NIX_CONFIG='experimental-features = nix-command flakes' \
    nix run github:nix-community/home-manager -- \
      -b hm-backup \
      switch \
      --flake "${build_dir}#${target_host}" \
      "$@"

  local rc=$?
  if [[ "$rc" -ne 0 ]]
  then
    return "$rc"
  fi

  new_link=$(hm::profile-link) || new_link=""
  new_gen=$(hm::profile-target) || new_gen=""

  if [[ -n "$current_gen" && -n "$new_gen" ]]
  then
    hm::show-generation-diff "$current_link" "$current_gen" "$new_link" "$new_gen"
  elif [[ -n "$new_gen" ]]
  then
    echo_info "Activated Home Manager generation: $new_gen"
  fi

  return "$rc"
}

alias nrb="hm::rebuild"

# vim: set ft=zsh et ts=2 sw=2 :
