DB="${AUTHELIA_DB:-/var/lib/authelia-main/db.sqlite3}"
BACKUP_ROOT="${AUTHELIA_BACKUP_ROOT:-/mnt/data/backups/authelia}"

usage() {
  cat <<USAGE
Usage: authelia-passkey-unfuck [--list] [CREDENTIAL_ID...]

Clear the latched WebAuthn clone warning and reset sign_count to 0, so the
next assertion of the real client passes. Without IDs, every credential with
clone_warning set is repaired. A SQLite backup is taken first.

  --list   show the stored credentials and exit
USAGE
}

list() {
  sqlite3 -cmd ".timeout 30000" -readonly -header -column "$DB" \
    'SELECT id, username, description, sign_count, clone_warning, last_used_at
     FROM webauthn_credentials'
}

main() {
  local ids=()
  local dir

  case "${1:-}" in
    -h | --help)
      usage
      return 0
      ;;
    --list)
      list
      return 0
      ;;
  esac

  if [[ $EUID -ne 0 ]]
  then
    echo "Must run as root" >&2
    return 1
  fi

  if [[ $# -gt 0 ]]
  then
    ids=("$@")
    if printf '%s\n' "${ids[@]}" | grep -qvE '^[0-9]+$'
    then
      echo "Credential IDs must be numeric" >&2
      return 2
    fi
  else
    mapfile -t ids < <(sqlite3 -cmd ".timeout 30000" "$DB" \
      'SELECT id FROM webauthn_credentials WHERE clone_warning = 1')
    if [[ ${#ids[@]} -eq 0 ]]
    then
      echo "No credential has clone_warning set"
      list
      return 0
    fi
  fi

  dir="$BACKUP_ROOT/$(date +%F-%H%M%S)-pre-unfuck"
  install -d -m 0700 "$dir"
  sqlite3 -cmd ".timeout 30000" "$DB" ".backup '$dir/db.sqlite3'"
  chmod 0600 "$dir/db.sqlite3"
  echo "Backup: $dir/db.sqlite3"

  sqlite3 -cmd ".timeout 30000" "$DB" "UPDATE webauthn_credentials
    SET clone_warning = 0, sign_count = 0
    WHERE id IN ($(IFS=,; echo "${ids[*]}"))"

  list
}

main "$@"
