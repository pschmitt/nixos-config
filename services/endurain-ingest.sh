# shellcheck shell=bash
# Upload new Gadgetbridge/OpenTracks activity files to Endurain.
# Wrapped by pkgs.writeShellApplication, which prepends the shebang and
# errexit/nounset/pipefail. Configuration comes from the environment, set by
# the systemd unit:
#   ENDURAIN_HOST, ENDURAIN_USERNAME, ENDURAIN_PASSWORD,
#   ENDURAIN_WATCH_DIR, ENDURAIN_STATE_DIR
#
# Triggered by a systemd .path unit (plus a sparse backstop timer). The watch
# dir is a receive-only Syncthing folder fed by the (send-only) phone, so we
# MUST NOT modify it: doing so would show up as "locally changed" items and any
# Syncthing re-sync/revert would re-present files. Instead we dedup by content
# hash via marker files in ENDURAIN_STATE_DIR. A marker means "handled, never
# upload again", written both for successful uploads and for permanently
# rejected files (e.g. a GPX with no track segments) so they stop retrying.
# Transient failures (auth/rate-limit/server/network) are left unmarked and
# retried on the next trigger.

host="${ENDURAIN_HOST:?}"
watch_dir="${ENDURAIN_WATCH_DIR:?}"
state_dir="${ENDURAIN_STATE_DIR:?}"
: "${ENDURAIN_USERNAME:?}"
: "${ENDURAIN_PASSWORD:?}"

mkdir -p "$state_dir"

# Collect only files we have not handled yet, keyed by content hash. We do this
# before logging in so that triggers with nothing new to do never touch the
# rate-limited login endpoint.
shopt -s nullglob nocaseglob
todo=()
declare -A todo_hash
for f in "$watch_dir"/*.fit "$watch_dir"/*.gpx "$watch_dir"/*.tcx; do
  [ -f "$f" ] || continue
  hash="$(sha256sum "$f" | cut -d' ' -f1)"
  [ -e "$state_dir/$hash" ] && continue
  todo+=("$f")
  todo_hash["$f"]="$hash"
done

if [ "${#todo[@]}" -eq 0 ]; then
  echo 'endurain-ingest: nothing new'
  exit 0
fi

login() {
  local resp code token
  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H 'X-Client-Type: mobile' \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "username=$ENDURAIN_USERNAME" \
      --data-urlencode "password=$ENDURAIN_PASSWORD" \
      "https://$host/api/v1/auth/login"
  )" || code='000'
  if [ "$code" != '200' ]; then
    echo "login failed (HTTP $code)" >&2
    rm -f "$resp"
    return 1
  fi
  if [ "$(jq -r '.mfa_required // false' <"$resp")" = 'true' ]; then
    echo 'login requires MFA; unattended ingest cannot proceed' >&2
    rm -f "$resp"
    return 1
  fi
  token="$(jq -er '.access_token' <"$resp")" || {
    rm -f "$resp"
    return 1
  }
  rm -f "$resp"
  printf '%s\n' "$token"
}

token="$(login)"

uploaded=0
rejected=0
transient=0

for f in "${todo[@]}"; do
  hash="${todo_hash[$f]}"
  marker="$state_dir/$hash"
  base="$(basename "$f")"

  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H "Authorization: Bearer $token" \
      -H 'X-Client-Type: mobile' \
      -F "file=@$f" \
      "https://$host/api/v1/activities/create/upload"
  )" || code='000'
  body="$(head -c 300 "$resp")"
  rm -f "$resp"

  case "$code" in
    201)
      : >"$marker"
      uploaded=$((uploaded + 1))
      echo "uploaded: $base"
      ;;
    400 | 413 | 415 | 422)
      # The file itself is unacceptable (e.g. a GPX with no track segments).
      # Record it as handled so we do not retry it forever.
      printf 'rejected HTTP %s: %s\n' "$code" "$base" >"$marker"
      rejected=$((rejected + 1))
      echo "REJECTED (HTTP $code): $base: $body" >&2
      ;;
    *)
      # Auth/rate-limit/server/network error: leave unmarked to retry later.
      transient=$((transient + 1))
      echo "TRANSIENT (HTTP $code), will retry: $base: $body" >&2
      ;;
  esac
done

echo "endurain-ingest: uploaded=$uploaded rejected=$rejected transient=$transient"

# Only signal failure for transient problems; permanently rejected files are
# recorded and must not keep the unit flapping.
[ "$transient" -eq 0 ]
