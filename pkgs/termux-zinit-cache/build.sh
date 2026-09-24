#!/usr/bin/env bash

set -Eeuo pipefail

cleanup_temp_root=''
cleanup_output_dir=''

cleanup() {
  local build_status=$?

  if [[ -n "$cleanup_temp_root" ]]
  then
    rm -rf -- "$cleanup_temp_root"
  fi
  if [[ -n "$cleanup_output_dir" && -d "$cleanup_output_dir" ]]
  then
    chmod 0700 "$cleanup_output_dir" 2>/dev/null || true
    if [[ "$build_status" -ne 0 ]]
    then
      rm -f -- \
        "$cleanup_output_dir/zinit-cache.tar.gz" \
        "$cleanup_output_dir/zinit-cache.tar.gz.sha256" \
        "$cleanup_output_dir/zinit-cache.manifest"
    fi
  fi
  return "$build_status"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") SOURCE_ROOT OUTPUT_DIR

Builds a Termux APT zsh and tmux plugin cache with Docker. SOURCE_ROOT must be
a private yadm worktree or a temporary snapshot containing the required
.config/zsh, .config/tmux, and Termux package list files. The source is mounted
read-only and is never added to a Nix derivation or Docker build context.

Set YADM_ZSH_TREE, YADM_TMUX_TREE, and YADM_TERMUX_PACKAGES_BLOB to the Git
object IDs that identify those inputs. TERMUX_ZINIT_TIMEOUT defaults to 90m.
EOF
}

main() {
  local source_root output_dir docker_platform termux_base_image docker_context temp_root staging_dir env_dir verify_dir
  local zsh_tree tmux_tree packages_blob zinit_timeout input_path object_id output_file file_path file_description
  local -a docker_binfmt_mounts=()

  umask 077

  if [[ "${1:-}" == -h || "${1:-}" == --help ]]
  then
    usage
    return 0
  fi

  if [[ "$#" -ne 2 ]]
  then
    printf 'Expected SOURCE_ROOT and OUTPUT_DIR\n' >&2
    usage >&2
    return 2
  fi

  source_root=$(realpath "$1")
  output_dir=$(realpath -m "$2")
  docker_platform=${TERMUX_DOCKER_PLATFORM:-linux/arm64}
  termux_base_image=${TERMUX_BASE_IMAGE:-termux/termux-docker:aarch64}
  docker_context=${TERMUX_CACHE_DOCKER_CONTEXT:?Nix package did not set Docker context}

  zsh_tree=${YADM_ZSH_TREE:?YADM_ZSH_TREE is required}
  tmux_tree=${YADM_TMUX_TREE:?YADM_TMUX_TREE is required}
  packages_blob=${YADM_TERMUX_PACKAGES_BLOB:?YADM_TERMUX_PACKAGES_BLOB is required}
  zinit_timeout=${TERMUX_ZINIT_TIMEOUT:-90m}
  if [[ ! "$zinit_timeout" =~ ^[[:digit:]]+[smhd]?$ ]]
  then
    printf 'TERMUX_ZINIT_TIMEOUT must be a duration such as 30m or 2h\n' >&2
    return 2
  fi

  for object_id in "$zsh_tree" "$tmux_tree" "$packages_blob"
  do
    if [[ ! "$object_id" =~ ^[[:xdigit:]]{40,64}$ ]]
    then
      printf 'Input metadata must be Git object IDs\n' >&2
      return 2
    fi
  done

  for input_path in \
    .config/zsh/zshrc \
    .config/tmux/tmux.conf \
    .config/yadm/ansible-bootstrap/roles/cli/vars/packages_termux.yml
  do
    if [[ ! -f "$source_root/$input_path" ]]
    then
      printf 'Required input is missing: %s\n' "$input_path" >&2
      return 2
    fi
  done

  mkdir -p "$output_dir"
  chmod 0700 "$output_dir"
  cleanup_output_dir="$output_dir"
  if [[ -n "$(ls -A "$output_dir")" ]]
  then
    printf 'Output directory must be empty: %s\n' "$output_dir" >&2
    return 2
  fi

  temp_root=$(mktemp -d)
  cleanup_temp_root="$temp_root"
  trap cleanup EXIT
  staging_dir="$temp_root/input"
  env_dir="$temp_root/usr-bin"
  mkdir -p "$staging_dir"
  mkdir -p "$env_dir"
  ln -s /data/data/com.termux/files/usr/bin/env "$env_dir/env"
  tar \
    --exclude='.config/zsh/secrets.zsh' \
    --exclude='.config/zsh/custom/hosts' \
    -cf - \
    -C "$source_root" \
    .config/zsh \
    .config/tmux \
    .config/yadm/ansible-bootstrap/roles/cli/vars/packages_termux.yml |
    tar -xf - -C "$staging_dir"

  if [[ "$docker_platform" == linux/arm64 && "$(uname -m)" == x86_64 ]]
  then
    if [[ ! -r /run/binfmt/aarch64-linux || ! -d /nix/store ]]
    then
      printf 'This x86_64 host lacks the configured AArch64 NixOS binfmt handler\n' >&2
      return 1
    fi
  docker_binfmt_mounts=(
      -v /run/binfmt/aarch64-linux:/run/binfmt/aarch64-linux:ro
      -v /nix/store:/nix/store:ro
    )
  fi

  chmod 0733 "$output_dir"
  if ! docker run --rm \
    --security-opt seccomp:unconfined \
    --platform "$docker_platform" \
    "${docker_binfmt_mounts[@]}" \
    -v "$staging_dir:/input:ro" \
    -v "$docker_context/prepare-termux-zinit-cache.sh:/tmp/prepare-termux-zinit-cache.sh:ro" \
    -v "$env_dir:/usr/bin:ro" \
    -v "$output_dir:/output" \
    "$termux_base_image" \
    bash -c 'umask 077; exec bash /tmp/prepare-termux-zinit-cache.sh "$@"' \
    termux-cache "$zsh_tree" "$tmux_tree" "$packages_blob" "$zinit_timeout" \
    >"$output_dir/container.log" 2>&1
  then
    printf 'Termux container failed; private diagnostics are in %s/container.log\n' "$output_dir" >&2
    return 1
  fi
  chmod 0700 "$output_dir"

  rm -f -- "$output_dir/container.log" "$output_dir/zinit-install.log" "$output_dir/tmux-plugin-install.log"

  for output_file in zinit-cache.tar.gz zinit-cache.tar.gz.sha256 zinit-cache.manifest
  do
    if [[ ! -s "$output_dir/$output_file" ]]
    then
      printf 'Build did not produce %s\n' "$output_file" >&2
      return 1
    fi
  done

  if ! (cd "$output_dir" && sha256sum --check --status zinit-cache.tar.gz.sha256)
  then
    printf 'Built archive checksum validation failed\n' >&2
    return 1
  fi

  verify_dir="$temp_root/verify"
  mkdir -p "$verify_dir"
  tar -xzf "$output_dir/zinit-cache.tar.gz" -C "$verify_dir" bin lib
  while IFS= read -r -d '' file_path
  do
    file_description=$(file -b "$file_path")
    if [[ "$file_description" == *ELF* && "$file_description" != *'ARM aarch64'* ]]
    then
      printf 'Built archive contains a non-AArch64 executable under %s\n' "${file_path#"$verify_dir"/}" >&2
      return 1
    fi
  done < <(find "$verify_dir/bin" "$verify_dir/lib" -type f -print0)

  if tar -tzf "$output_dir/zinit-cache.tar.gz" | grep -Ev '^(share|bin|lib)(/|$)' | grep -q .
  then
    printf 'Built archive contains a disallowed path\n' >&2
    return 1
  fi

  chmod 0600 "$output_dir"/*
  chmod 0700 "$output_dir"
  printf 'Built Termux cache in %s\n' "$output_dir"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=bash et ts=2 sw=2 :
