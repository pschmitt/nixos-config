#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [--flake FLAKE_URI] TARGET_HOST"
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

    tree
  )
}

main() {
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  local flake_uri="." # "github:pschmitt/nixos-config"

  while [[ -n $* ]]
  do
    case "$1" in
      -h|--help|-\?)
        usage
        return 0
        ;;
      -f|--flake*)
        flake_uri="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  local target_host="$1"

  if [[ -z $target_host ]]
  then
    echo "Error: TARGET_HOST is required." >&2
    usage >&2
    return 2
  fi

  local tmpdir
  tmpdir="$(mktemp -d)" || return 7
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" EXIT

  decrypt_host_secrets "$target_host" "$tmpdir"

  # append host name if not set already
  if [[ "$flake_uri" != *#* ]]
  then
    flake_uri="${flake_uri}#${target_host}"
  fi

  # TODO And ---disk-encryption-keys maybe?
  echo nix run github:nix-community/nixos-anywhere -- \
    --flake "$flake_uri" \
    --target-host "$target_host" \
    --build-on local \
    --disko-mode disko \
    --disk-encryption-keys /tmp/disk-1.key "${tmpdir}/luks-passphrase-root.txt" \
    --extra-files "${tmpdir}/files" \
    -i ~/.ssh/id_ed25519 \
    "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
