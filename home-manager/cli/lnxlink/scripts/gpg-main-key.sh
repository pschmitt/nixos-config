#!/usr/bin/env bash

gpg_main_fingerprint() {
  gpg --batch --list-secret-keys --with-colons --fingerprint 2>/dev/null |
    awk -F: '$1 == "fpr" { print $10; exit }'
}

main() {
  local fpr
  fpr=$(gpg_main_fingerprint)

  if [[ -z "$fpr" ]]
  then
    echo false
    return
  fi

  if printf '' | gpg --batch --pinentry-mode error \
    --local-user "$fpr" --sign --armor --output /dev/null 2>/dev/null
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
