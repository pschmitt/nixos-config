#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [--force] [--optimist|--oci] NEW_HOSTNAME"
}

main() {
  local FORCE=${FORCE:-}
  local NEW_HOSTNAME=${NEW_HOSTNAME:-}
  local TEMPLATE_TYPE=${TEMPLATE_TYPE:-optimist}

  while [[ -n $* ]]
  do
    case "$1" in
      -h|--help|-\?)
        usage
        return 0
        ;;
      -f|--force)
        FORCE=1
        shift
        ;;
      --oci)
        TEMPLATE_TYPE="oci"
        shift
        ;;
      --openstack|--optimist)
        TEMPLATE_TYPE="optimist"
        shift
        ;;
      --raw)
        TEMPLATE_TYPE="raw"
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  NEW_HOSTNAME="$1"

  if [[ -z "$NEW_HOSTNAME" ]]
  then
    echo "Error: No hostname provided." >&2
    usage >&2
    return 2
  fi

  # nix config
  local DEST="./hosts/$NEW_HOSTNAME"

  if [[ -d "$DEST" ]]
  then
    if [[ -n "$FORCE" ]]
    then
      rm -rf "$DEST"
    else
      echo "Error: Config for '$NEW_HOSTNAME' already exists." >&2
      return 1
    fi
  fi

  cp -va "./templates/nix/${TEMPLATE_TYPE}" "$DEST"
  printf '%s' "$NEW_HOSTNAME" > "${DEST}/HOSTNAME"
  ./secrets/sops-init.sh "$NEW_HOSTNAME"

  # tofu config
  if [[ "$TEMPLATE_TYPE" == "raw" ]]
  then
    echo "Raw template does not support tofu configuration."
    return 0
  fi

  sed "s#\${REPLACEME}#${NEW_HOSTNAME}#g" "./templates/tofu/${TEMPLATE_TYPE}/host.tf" \
    > "./tofu/${NEW_HOSTNAME}.tf"

  echo "Config created for $NEW_HOSTNAME"
  echo "To deploy, run:"
  echo "./tofu/tofu.sh init && ./tofu/tofu.sh apply -target=module.nix-${NEW_HOSTNAME}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  main "$@"
fi
