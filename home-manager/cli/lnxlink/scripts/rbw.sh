#!/usr/bin/env bash

main() {
  if ECHO_NO_COLOR=1 ECHO_NO_EMOJI=1 rbw unlocked >/dev/null 2>&1
  then
    echo true
  else
    echo false
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
