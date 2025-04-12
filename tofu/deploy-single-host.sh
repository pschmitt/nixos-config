#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

while [[ -n $* ]]
do
  case "$1" in
    -f|--force|-d|--delete|-r|--recreate)
      DELETE=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

TARGET_HOST="${1:-$TARGET_HOST}"
if [[ -n "$DELETE" ]]
then
  # TODO This *only* works for OpenStack VMs, we need to dynamically determine
  # what type of object we are dealing with here
  # -> grep the state list like this?
  # ./tofu.sh state list | grep -E 'instance.*\.(rofl-07|oci_03|oci-03)'
  ./tofu.sh destroy -auto-approve -target="openstack_compute_instance_v2.${TARGET_HOST}"
fi

./tofu.sh apply -auto-approve -target="module.nix-${TARGET_HOST}"
