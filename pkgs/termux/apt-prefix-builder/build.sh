#!/usr/bin/env bash

set -Eeuo pipefail

cleanup_temp_root=''

main() {
  local source_root output_dir docker_platform termux_base_image docker_context temp_root staging_dir env_dir
  local archive_paths prefix_path file_description file_path
  local packages_blob=${YADM_TERMUX_PACKAGES_BLOB:?YADM_TERMUX_PACKAGES_BLOB is required}
  local -a docker_binfmt_mounts=()

  if (($# != 2))
  then
    printf 'Usage: %s SOURCE_ROOT OUTPUT_DIR\n' "$(basename "$0")" >&2
    return 2
  fi

  source_root=$(realpath "$1")
  output_dir=$(realpath -m "$2")
  docker_platform=${TERMUX_DOCKER_PLATFORM:-linux/arm64}
  termux_base_image=${TERMUX_BASE_IMAGE:-termux/termux-docker:aarch64}
  docker_context=${TERMUX_PREFIX_BUILDER_CONTEXT:?Nix package did not set the Docker context}

  if [[ ! -f "$source_root/.config/yadm/ansible-bootstrap/roles/cli/vars/packages_termux.yml" ]]
  then
    printf 'Termux package list is missing from the build source\n' >&2
    return 2
  fi
  if [[ "$docker_platform" == linux/arm64 && "$(uname -m)" == x86_64 ]] &&
    [[ ! -r /run/binfmt/aarch64-linux || ! -d /nix/store ]]
  then
    printf 'This x86_64 host lacks the configured AArch64 NixOS binfmt handler\n' >&2
    return 1
  fi

  mkdir -p "$output_dir"
  chmod 0700 "$output_dir"
  if [[ -n "$(ls -A "$output_dir")" ]]
  then
    printf 'Output directory must be empty: %s\n' "$output_dir" >&2
    return 2
  fi

  temp_root=$(mktemp -d)
  cleanup_temp_root=$temp_root
  trap 'if [[ -n "$cleanup_temp_root" ]]; then rm -rf -- "$cleanup_temp_root"; fi' EXIT
  staging_dir="$temp_root/input"
  env_dir="$temp_root/usr-bin"
  mkdir -p "$staging_dir" "$env_dir"
  ln -s /data/data/com.termux/files/usr/bin/env "$env_dir/env"
  tar -cf - -C "$source_root" .config/yadm/ansible-bootstrap/roles/cli/vars/packages_termux.yml |
    tar -xf - -C "$staging_dir"

  if [[ "$docker_platform" == linux/arm64 && "$(uname -m)" == x86_64 ]]
  then
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
    -v "$docker_context/prepare-termux-prefix.sh:/tmp/prepare-termux-prefix.sh:ro" \
    -v "$env_dir:/usr/bin:ro" \
    -v "$output_dir:/output" \
    "$termux_base_image" \
    bash /tmp/prepare-termux-prefix.sh "$packages_blob" \
    >"$output_dir/container.log" 2>&1
  then
    printf 'Termux package build failed; diagnostics are in %s/container.log\n' "$output_dir" >&2
    return 1
  fi
  chmod 0700 "$output_dir"

  if [[ ! -s "$output_dir/termux-prefix.tar.gz" || ! -s "$output_dir/termux-prefix.tar.gz.sha256" || ! -s "$output_dir/termux-environment.manifest" ]]
  then
    printf 'The Termux package builder did not produce all expected outputs\n' >&2
    return 1
  fi
  if ! (cd "$output_dir" && sha256sum --check --status termux-prefix.tar.gz.sha256)
  then
    printf 'Termux prefix checksum validation failed\n' >&2
    return 1
  fi

  archive_paths="$temp_root/prefix-archive-paths"
  prefix_path="$temp_root/prefix"
  mkdir "$prefix_path"
  tar -tzf "$output_dir/termux-prefix.tar.gz" > "$archive_paths"
  if grep -Ev '^usr(/|$)' "$archive_paths" >/dev/null ||
    grep -Eq '(^/|(^|/)\.\.(/|$))' "$archive_paths"
  then
    printf 'Termux prefix archive contains an unsafe path\n' >&2
    return 1
  fi
  if grep -Eq '^usr/etc/ssh/ssh_host_.*_key(\.pub)?$' "$archive_paths"
  then
    printf 'Termux prefix archive contains generated SSH host keys\n' >&2
    return 1
  fi

  for service in sshd ssh-agent
  do
    if ! grep -Fxq "usr/var/service/$service/down" "$archive_paths"
    then
      printf 'Termux prefix archive does not keep %s disabled\n' "$service" >&2
      return 1
    fi
  done

  tar -xzf "$output_dir/termux-prefix.tar.gz" -C "$prefix_path"
  while IFS= read -r -d '' file_path
  do
    file_description=$(file -b "$file_path")
    if [[ "$file_description" == *ELF* && "$file_description" != *'ARM aarch64'* ]]
    then
      printf 'Termux prefix contains a non-AArch64 executable or shared library: %s\n' "$file_path" >&2
      return 1
    fi
  done < <(
    timeout 5m find "$prefix_path/usr/bin" "$prefix_path/usr/lib" -type f \
      \( -perm /111 -o -name '*.so' -o -name '*.so.*' \) \
      -print0
  )

  rm -f -- "$output_dir/container.log"
  chmod 0600 "$output_dir"/*
  chmod 0700 "$output_dir"
  printf 'Built Termux APT prefix in %s\n' "$output_dir"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
