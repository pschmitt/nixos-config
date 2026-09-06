#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  killall slurp still # swappy

  tmp=$(mktemp --suffix=.png)
  trap 'rm -f "${tmp}"' EXIT

  still -c 'slurp | grim -g- -' | tee >(wl-copy) > "${tmp}"
  swappy -f "${tmp}" -o "${tmp}"
  wl-copy < "${tmp}"
fi
