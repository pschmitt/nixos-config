#!/usr/bin/env bash

if [[ "$#" -eq 0 ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
  set -- ./terraform.tfvars.sops.json
fi

SOPS_AGE_KEY=$(ssh-to-age --private-key <~/.ssh/id_ed25519) sops "$@"
