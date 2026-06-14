#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor reflecting the unlock status of the
# primary secret GPG key.

export GNUPGHOME="${GNUPGHOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/gnupg}"

# Is the secret key for $1 (email/uid) unlocked in the gpg-agent cache?
# Replaces the zhj `gpg::is-unlocked` helper.
gpg_key_is_unlocked() {
  local email="$1" keygrips kg
  keygrips="$(gpg --fingerprint --with-keygrip "$email" 2>/dev/null \
    | awk '/^[[:space:]]+Keygrip[[:space:]]+/ { print $3 }')"
  [[ -z "$keygrips" ]] && return 1

  for kg in $keygrips
  do
    if gpg-connect-agent "KEYINFO --no-ask ${kg} Err Pmt Des" /bye 2>/dev/null \
      | awk -v kg="$kg" '
          $1 == "S" && $2 == "KEYINFO" && $3 == kg { if ($7 == "1") found = 1 }
          END { exit (found ? 0 : 1) }'
    then
      return 0
    fi
  done
  return 1
}

main_gpg_uid() {
  gpg --batch --homedir "$GNUPGHOME" --list-secret-keys --with-colons --fingerprint 2>/dev/null | \
    awk -F: '
      $1 == "fpr" && fpr == "" { fpr = $10; next }
      $1 == "uid" && uid == "" { uid = $10 }
      END {
        if (uid != "") {
          printf "%s\t%s\n", uid, fpr
        } else {
          exit 1
        }
      }
    '
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:key-variant"
  local message="No GPG secret key found"
  local uid=""
  local fingerprint=""

  if IFS=$'\t' read -r uid fingerprint < <(main_gpg_uid)
  then
    message="Main GPG key is locked"

    if gpg_key_is_unlocked "$uid" >/dev/null 2>&1
    then
      state=true
      message="Main GPG key is unlocked"
    fi
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --arg message "$message" \
    --arg uid "$uid" \
    --arg fingerprint "$fingerprint" \
    '
      def attrs:
        ({ message: $message }
          | (if $uid != "" then . + {uid: $uid} else . end)
          | (if $fingerprint != "" then . + {fingerprint: $fingerprint} else . end)
        );

      {
        schedule: "@every 30s",
        sensors: [
          {
            sensor_name: "GPG Main Key",
            sensor_type: "binary",
            sensor_icon: $icon,
            sensor_device_class: "lock",
            sensor_state: $state,
            sensor_attributes: attrs
          }
        ]
      }
    '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
