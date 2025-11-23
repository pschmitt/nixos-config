#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  if command -v wleave &>/dev/null
  then
    cd ~/.config/wleave || exit 9
    exec wleave -f -k "$@"
  fi

  if command -v wlogout &>/dev/null
  then
    exec wlogout "$@"
  fi
fi
