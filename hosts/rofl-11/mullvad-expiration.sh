#!/bin/bash

usage() {
  echo "Usage: $0 [--warning WARNING_DAYS] ACCOUNT_NUMBER"
  echo "  --warning WARNING_DAYS    Set the warning threshold in days (default: 7)"
  echo "  ACCOUNT_NUMBER            The account number to check"
}

get_account_info() {
  local account_number="$1"
  curl -fsSL "https://api.mullvad.net/public/accounts/v1/${account_number}"
}

check_expiration() {
  local account_info="$1"
  local warning_days="$2"

  local remaining_days
  remaining_days="$(remaining_days "$account_info")"

  [[ "$remaining_days" -le "$warning_days" ]]
}

remaining_days() {
  local account_info="$1"
  local expiration_date
  expiration_date="$(jq -r '.expiry' <<< "$account_info")"

  local remaining_days
  echo $(( ( $(date -u -d "$expiration_date" +%s) - $(date -u +%s) ) / 86400 ))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then

  WARNING_DAYS=7
  ACCOUNT_NUMBER=""

  while (( $# ))
  do
    case $1 in
      -w|--warning|-t|--threshold)
        WARNING_DAYS="$2"
        shift 2
        ;;
      --help)
        usage
        return
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -e "$1" ]]
  then
    echo "Reading account number from file $1." >&2
    ACCOUNT_NUMBER="$(cat "$1")"
  else
    ACCOUNT_NUMBER="$1"
  fi

  if [[ -z "$ACCOUNT_NUMBER" ]]
  then
    usage
    exit 2
  fi

  ACCOUNT_INFO="$(get_account_info "$ACCOUNT_NUMBER")"

  if [[ -z "$ACCOUNT_INFO" ]] || ! jq -e . &>/dev/null <<< "$ACCOUNT_INFO"
  then
    echo "Error: Unable to fetch account info." >&2
    exit 1
  fi

  REMAINING_DAYS="$(remaining_days "$ACCOUNT_INFO")"
  if [[ "$REMAINING_DAYS" -gt 0 ]]
  then
    echo "✔️ Account is active."
    echo "📅 Remaining days: $REMAINING_DAYS"
  else
    echo "🚨 Account INACTIVE."
    exit 1
  fi

  if check_expiration "$ACCOUNT_INFO" "$WARNING_DAYS"
  then
    echo "😱 Your account is about to expire in less than $WARNING_DAYS days!"
    exit 1
  else
    echo "✅ Your account is not expiring within the next $WARNING_DAYS days."
  fi
fi

# vim:ts=2:sw=2:expandtab
