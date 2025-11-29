#!/usr/bin/env bash

set -euo pipefail

# Ensure we are in the script's directory (repo root)
cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [ARGS...]

Commands:
  remote [OPTS] TARGET_HOST   Install NixOS on a remote host using nixos-anywhere
  local HOSTNAME DISK         Install NixOS on a local disk using disko-install

Options (remote):
  -f, --flake URI       Flake URI (default: .)
  -H, --ssh-host HOST   SSH host to connect to (default: TARGET_HOST)

Options (general):
  -k, --dry-run         Dry run (print commands without executing)

Examples:
  $(basename "$0") remote x13
  $(basename "$0") remote --ssh-host root@192.168.1.5 x13
  $(basename "$0") local x13 /dev/nvme0n1
EOF
}

decrypt_host_secrets() {
  local target_host="$1" tmpdir="$2"
  local tofu_script_dir="${PWD}/tofu/scripts"
  (
    export TARGET_HOST="$target_host" # the tofu scripts need this env var

    # in ./files/ we put the files we want to copy to the host
    mkdir -p "${tmpdir}/files"
    cd "${tmpdir}/files" || exit 9
    "${tofu_script_dir}/decrypt-ssh-secrets.sh" || exit 1

    # the luks root passphrase goes to the root of the tmpdir, we don't want to
    # copy this file
    cd "$tmpdir" || exit 9
    "${tofu_script_dir}/decrypt-luks-passphrase.sh" > luks-passphrase-root.txt || exit 1

    if command -v tree >/dev/null
    then
      tree
    fi
  )
}

cmd_remote() {
  local flake_uri="."
  local ssh_host
  local target_host
  local args=()
  local dry_run

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -k|--dry-run|--dryrun)
        dry_run=1
        shift
        ;;
      -f|--flake*)
        flake_uri="$2"
        shift 2
        ;;
      -H|--ssh-host*)
        ssh_host="$2"
        shift 2
        ;;
      --)
        shift
        args+=("$@")
        break
        ;;
      *)
        if [[ -z "${target_host:-}" ]]
        then
          target_host="$1"
        else
          args+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z "${target_host:-}" ]]
  then
    echo "Error: TARGET_HOST is required." >&2
    usage >&2
    exit 2
  fi

  ssh_host="${ssh_host:-$target_host}"

  local tmpdir
  tmpdir="$(mktemp -d)" || exit 7
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" EXIT

  if [[ -n ${dry_run:-} ]]
  then
    echo "Would decrypt host secrets to ${tmpdir}..."
  else
    decrypt_host_secrets "$target_host" "$tmpdir"
  fi

  # append host name if not set already
  if [[ "$flake_uri" != *#* ]]
  then
    flake_uri="${flake_uri}#${target_host}"
  fi

  local cmd=(nix run github:nix-community/nixos-anywhere -- \
    --flake "$flake_uri" \
    --target-host "$ssh_host" \
    --build-on local \
    --disko-mode disko \
    --disk-encryption-keys /tmp/disk-1.key "${tmpdir}/luks-passphrase-root.txt" \
    --extra-files "${tmpdir}/files" \
    -i ~/.ssh/id_ed25519 \
    "${args[@]}")

  if [[ -n ${dry_run:-} ]]
  then
    echo "\$ ${cmd[*]}"
  else
    "${cmd[@]}"
  fi
}

cmd_local() {
  local target_hostname
  local disk
  local args=()
  local dry_run

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -k|--dry-run|--dryrun)
        dry_run=1
        shift
        ;;
      --)
        shift
        args+=("$@")
        break
        ;;
      *)
        if [[ -z "${target_hostname:-}" ]]
        then
          target_hostname="$1"
        elif [[ -z "${disk:-}" ]]
        then
          disk="$1"
        else
          args+=("$1")
        fi
        shift
        ;;
    esac
  done

  if [[ -z "${target_hostname:-}" || -z "${disk:-}" ]]
  then
    echo "Error: HOSTNAME and DISK are required for local install." >&2
    usage >&2
    exit 2
  fi

  local cmd=(sudo nix --experimental-features 'nix-command flakes' \
    run 'github:nix-community/disko/latest#disko-install' -- \
      --mode format \
      --flake ".#${target_hostname}" \
      --disk main "$disk" \
      "${args[@]}")

  if [[ -n ${dry_run:-} ]]
  then
    echo "${cmd[*]}"
  else
    set -x
    "${cmd[@]}"
  fi
}

main() {
  local args=()
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      remote)
        shift
        cmd_remote "${args[@]}" "$@"
        return
        ;;
      local)
        shift
        cmd_local "${args[@]}" "$@"
        return
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#args[@]} -gt 0 ]]
  then
    echo "Error: Unknown command '${args[0]}'" >&2
  fi

  usage
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
