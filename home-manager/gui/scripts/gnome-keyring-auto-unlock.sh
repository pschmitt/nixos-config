#!/usr/bin/env bash

keyring_locked() {
  local coll
  for coll in $(busctl -j --user --no-pager get-property \
    org.freedesktop.secrets /org/freedesktop/secrets \
    org.freedesktop.Secret.Service Collections 2>/dev/null | jq -er '.data[]' 2>/dev/null)
  do
    if busctl -j --user --no-pager get-property \
      org.freedesktop.secrets "$coll" \
      org.freedesktop.Secret.Collection Locked 2>/dev/null | jq -e '.data' >/dev/null 2>&1
    then
      return 0 # at least one collection is locked
    fi
  done
  return 1
}

main() {
  local secret_file="${1:?Missing secret path}"

  if ! keyring_locked
  then
    echo "Keyring already unlocked"
    return 0
  fi

  if [[ ! -r "$secret_file" ]]
  then
    echo "No keyring password secret at $secret_file, skipping" >&2
    return 0
  fi

  # gnome-keyring-unlock reads the password from stdin (no trailing newline).
  printf '%s' "$(< "$secret_file")" | gnome-keyring-unlock

  # Touching a secret forces the (now unlocked) login keyring to settle.
  date -Iseconds | secret-tool store --label="gnome-keyring-auto-unlock" \
    app gnome-keyring-auto-unlock test unlock 2>/dev/null || true
  secret-tool clear app gnome-keyring-auto-unlock test unlock 2>/dev/null || true

  if keyring_locked
  then
    echo "Failed to unlock keyring" >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
