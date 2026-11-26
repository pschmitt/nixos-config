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
# Syncthing re-sync/revert would re-present files. Instead we dedup LOCAL
# retries by content hash via marker files in ENDURAIN_STATE_DIR. A marker
# means "handled, never upload again", written for successful uploads,
# server-side duplicates and permanently rejected files (e.g. a GPX with no
# track segments) so they stop retrying. Transient failures (auth/rate-limit/
# server/network) are left unmarked and retried on the next trigger.
#
# Content-hash dedup only catches re-syncs of the exact same file. It cannot
# catch the same real-world activity arriving as two different files - e.g.
# two phones both running Gadgetbridge exporting the same watch session a
# few seconds apart, or an activity Endurain already has via some other sync
# path entirely (its Strava/Garmin Connect integrations, observed creating
# same-second duplicates outside this script's control). check_duplicate
# guards against both by asking Endurain itself whether an activity already
# starts within DEDUP_WINDOW_SECONDS of this GPX's first trackpoint, before
# ever uploading.

# Gadgetbridge/OpenTracks GPX <type> values (lower-cased ActivityKind names)
# that Endurain does not recognise, mapped onto strings it does. Endurain
# falls back to its generic "Workout" type for anything unknown, and such
# activities never get default gear assigned. Values it already understands
# verbatim - walking, hiking, cycling, treadmill, indoor_cycling, rowing,
# yoga, strength_training - are deliberately absent and pass through.
declare -A GPX_TYPE_MAP=(
  [outdoor_running]='running'
  [street_running]='running'
  [indoor_running]='treadmill'
  [cross_country_running]='running'
  [ultra_run]='running'
  [trail_run]='trail running'
  [track_run]='track running'
  [virtual_run]='virtualrun'
  [outdoor_walking]='walking'
  [race_walking]='walking'
  [outdoor_cycling]='cycling'
  [trail_hike]='hiking'
  [mountain_hike]='hiking'
  [pool_swim]='lap_swimming'
  [swimming_openwater]='open_water_swimming'
  [rowing_machine]='indoor_rowing'
  [table_tennis]='tabletennis'
)

# How close two activities' start times must be to count as the same
# real-world session. Observed duplicates were 2s apart; 300s leaves plenty
# of margin while still being far shorter than the gap between two genuinely
# separate activities on the same day.
DEDUP_WINDOW_SECONDS="${ENDURAIN_DEDUP_WINDOW_SECONDS:-300}"
# How many of the most recent activities to compare against.
DEDUP_LOOKBACK=20
# A path event can arrive just before Syncthing finishes presenting a file.
# Retry empty scans briefly before declaring that there is nothing to ingest.
EMPTY_SCAN_RETRIES=3
EMPTY_SCAN_RETRY_SECONDS=10
UPLOAD_POLL_ATTEMPTS=90
UPLOAD_POLL_SECONDS=2

# Filled by collect_todo, consumed by main.
todo=()
declare -A todo_hash

# Set by rewrite_gpx_type/fix_gpx_spikes: a scratch copy to upload instead of
# the original, or empty when the file needs no change. Set by upload_file:
# uploaded, rejected or transient. Globals rather than stdout, so all three
# functions stay free to log to the journal.
rewritten_path=""
despiked_path=""
upload_outcome=""

log() {
  printf '%s\n' "$*"
}

err() {
  printf '%s\n' "$*" >&2
}

# Collect only files we have not handled yet, keyed by content hash. We do this
# before logging in so that triggers with nothing new to do never touch the
# rate-limited login endpoint.
collect_todo() {
  local watch_dir="$1"
  local state_dir="$2"
  local f
  local hash

  shopt -s nullglob nocaseglob
  for f in "$watch_dir"/*.fit "$watch_dir"/*.gpx "$watch_dir"/*.tcx
  do
    if [[ ! -f "$f" ]]
    then
      continue
    fi
    hash="$(sha256sum "$f" | cut -d' ' -f1)"
    if [[ -e "$state_dir/$hash" ]]
    then
      continue
    fi
    todo+=("$f")
    todo_hash["$f"]="$hash"
  done
}

login() {
  local host="$1"
  local dir resp code token verifier challenge next_step session_id device_id

  dir="$(mktemp -d)"
  resp="$dir/response"
  printf '%s' "$ENDURAIN_USERNAME" >"$dir/username"
  printf '%s' "$ENDURAIN_PASSWORD" >"$dir/password"
  verifier="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"
  challenge="$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=\n')"
  device_id="$(cat "$ENDURAIN_STATE_DIR/device-id" 2>/dev/null || true)"

  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H 'X-Client-Type: mobile' \
      -H "X-Device-Id: $device_id" \
      --data-urlencode "username@$dir/username" \
      --data-urlencode "password@$dir/password" \
      --data-urlencode "code_challenge=$challenge" \
      --data-urlencode 'code_challenge_method=S256' \
      "https://$host/api/v1/auth/login"
  )" || code='000'

  if [[ "$code" != '200' ]]
  then
    err "login failed (HTTP $code)"
    rm -rf "$dir"
    return 1
  fi

  next_step="$(jq -r '.next_step // empty' <"$resp")"
  if [[ "$(jq -r '.mfa_required // false' <"$resp")" == 'true' ]] || [[ "$next_step" == 'mfa' ]]
  then
    err 'login requires MFA; unattended ingest cannot proceed'
    rm -rf "$dir"
    return 1
  fi

  if [[ "$next_step" == 'exchange' ]]
  then
    session_id="$(jq -er '.session_id | strings | select(test("^[0-9a-fA-F-]+$"))' <"$resp")" || {
      err 'login returned an invalid session id'
      rm -rf "$dir"
      return 1
    }
    device_id="$(jq -r '.device_id // empty' <"$resp")"
    code="$(
      PKCE_VERIFIER="$verifier" jq -cn '{code_verifier: env.PKCE_VERIFIER}' |
        curl -sS -o "$resp" -w '%{http_code}' \
          -H 'X-Client-Type: mobile' \
          -H "X-Device-Id: $device_id" \
          -H 'Content-Type: application/json' --data-binary @- \
          "https://$host/api/v1/auth/sessions/$session_id/tokens"
    )" || code='000'
    if [[ "$code" != '200' ]]
    then
      err "token exchange failed (HTTP $code)"
      rm -rf "$dir"
      return 1
    fi
    next_step="$(jq -r '.next_step // empty' <"$resp")"
  fi

  if [[ -n "$next_step" ]] && [[ "$next_step" != 'tokens' ]]
  then
    err "unsupported sign-in step: $next_step"
    rm -rf "$dir"
    return 1
  fi
  token="$(jq -er '.access_token | strings | select(length > 0)' <"$resp")" || {
    err 'login returned no access token'
    rm -rf "$dir"
    return 1
  }
  device_id="$(jq -r '.device_id // empty' <"$resp")"
  if [[ -n "$device_id" ]]
  then
    umask 077
    printf '%s' "$device_id" >"$ENDURAIN_STATE_DIR/device-id"
  fi
  rm -rf "$dir"
  printf '%s\n' "$token"
}

# Print the start_time of our DEDUP_LOOKBACK most recent activities, one per
# line. Best-effort: prints nothing on any failure, which makes
# check_duplicate fail open (upload proceeds) rather than block ingestion on
# an API hiccup.
recent_start_times() {
  local host="$1"
  local token="$2"
  local resp
  local code

  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H @<(printf 'Authorization: Bearer %s\n' "$token") \
      -H 'X-Client-Type: mobile' \
      "https://$host/api/v1/activities?page_number=1&num_records=$DEDUP_LOOKBACK&sort_by=start_time&sort_order=desc"
  )" || code='000'

  if [[ "$code" == '200' ]]
  then
    jq -r '.items[]?.start_time // empty' <"$resp"
  fi
  rm -f "$resp"
}

# Sets is_duplicate=1 when an activity already exists within
# DEDUP_WINDOW_SECONDS of this GPX's first trackpoint. Only .gpx is checked
# (the only format seen duplicated in practice) and start_time comparisons
# happen in epoch seconds: the GPX's own <time> is UTC, and v0.20.0 returns
# Endurain activity start_time values as UTC-aware timestamps.
is_duplicate=""

# Extract the first trackpoint's <time>. A plain greedy `.*<time>...` sed
# match breaks on these files: they're a single unbroken line with no
# newlines, so `.*` backtracks all the way to the LAST <time> in the
# document (the activity's end, or worse the <metadata> block's own <time>,
# whichever comes last) instead of the first trkpt's. Splitting on <trkpt>
# first isolates trkpt #1 on its own line, where a greedy match is safe
# again because that single trkpt only ever has one <time>.
first_trkpt_time() {
  local f="$1"
  sed 's#<trkpt#\n<trkpt#g' "$f" | sed -n '2p' | sed -n 's#.*<time>\([^<]*\)</time>.*#\1#p'
}

check_duplicate() {
  local f="$1"
  local host="$2"
  local token="$3"
  local gpx_time
  local epoch
  local existing_start
  local existing_epoch
  local delta

  is_duplicate=""

  if [[ "$f" != *.gpx ]]
  then
    return 0
  fi

  gpx_time="$(first_trkpt_time "$f")"
  if [[ -z "$gpx_time" ]]
  then
    return 0
  fi

  epoch="$(date -d "$gpx_time" +%s)" || return 0

  while read -r existing_start
  do
    if [[ -z "$existing_start" ]]
    then
      continue
    fi
    existing_epoch="$(date -d "$existing_start" +%s)" || continue
    delta=$(( existing_epoch - epoch ))
    if (( delta > -DEDUP_WINDOW_SECONDS && delta < DEDUP_WINDOW_SECONDS ))
    then
      is_duplicate=1
      return 0
    fi
  done < <(recent_start_times "$host" "$token")
}

# Rewrite an unrecognised GPX <type> onto Endurain's vocabulary, on a scratch
# copy - the synced original is never touched. Gadgetbridge writes the raw
# ActivityKind enum name and lower-cased it in 2026-08 (upstream 9d872b136),
# so the lookup is case-insensitive: an exact match on the old upper-case
# spelling silently stopped firing when that landed.
rewrite_gpx_type() {
  local f="$1"
  local gpx_type
  local mapped

  rewritten_path=""

  if [[ "$f" != *.gpx ]]
  then
    return 0
  fi

  gpx_type="$(sed -n 's#.*<type>\([^<]*\)</type>.*#\1#p' "$f" | head -1)"
  if [[ -z "$gpx_type" ]]
  then
    return 0
  fi

  mapped="${GPX_TYPE_MAP[${gpx_type,,}]:-}"
  if [[ -z "$mapped" ]] || [[ "$mapped" == "$gpx_type" ]]
  then
    return 0
  fi

  rewritten_path="$(mktemp --suffix=.gpx)"
  sed "s#<type>[^<]*</type>#<type>$mapped</type>#g" "$f" >"$rewritten_path"
  log "type rewrite: $(basename "$f"): $gpx_type -> $mapped"
}

# Drop GPS-spike trackpoints before upload, on a scratch copy (only .gpx -
# see fix-gpx-spikes.py for the detection rule: a point must be anomalous on
# BOTH its incoming and outgoing leg, so a real point after a pause/resume
# gap is never touched). Its stdout is exactly the removed-point count;
# everything else it reports goes to stderr, which we pass through as-is.
fix_gpx_spikes() {
  local f="$1"
  local out
  local removed

  despiked_path=""

  if [[ "$f" != *.gpx ]]
  then
    return 0
  fi

  out="$(mktemp --suffix=.gpx)"
  if ! removed="$(fix-gpx-spikes "$f" "$out")"
  then
    err "fix-gpx-spikes failed on $(basename "$f"); uploading as-is"
    rm -f "$out"
    return 0
  fi

  if [[ "$removed" -eq 0 ]]
  then
    rm -f "$out"
    return 0
  fi

  log "despiked: $(basename "$f")"
  despiked_path="$out"
}

# Upload one file, setting upload_outcome to uploaded, rejected or transient.
poll_upload() {
  local host="$1"
  local token="$2"
  local job_id="$3"
  local base="$4"
  local marker="$5"
  local resp
  local code
  local status
  local error_code
  local attempt
  local job_route="jobs"

  for (( attempt = 1; attempt <= UPLOAD_POLL_ATTEMPTS; attempt++ ))
  do
    resp="$(mktemp)"
    code="$(
      curl -sS -o "$resp" -w '%{http_code}' \
        -H @<(printf 'Authorization: Bearer %s\n' "$token") \
        -H 'X-Client-Type: mobile' \
        "https://$host/api/v1/$job_route/$job_id"
    )" || code='000'

    if [[ "$code" == '404' ]] && [[ "$job_route" == 'jobs' ]]
    then
      job_route='activities/ingestion-jobs'
      rm -f "$resp"
      attempt=$((attempt - 1))
      continue
    fi

    if [[ "$code" != '200' ]]
    then
      err "TRANSIENT (job poll HTTP $code), will retry: $base"
      rm -f "$resp"
      upload_outcome='transient'
      return 0
    fi

    status="$(jq -r '.status // empty' <"$resp")"
    error_code="$(jq -r '.error_code // empty' <"$resp")"
    rm -f "$resp"

    case "$status" in
      completed | succeeded)
        : >"$marker"
        log "uploaded: $base"
        upload_outcome='uploaded'
        return 0
        ;;
      failed)
        case "$error_code" in
          unsupported_format | invalid_file | no_activities_found)
            printf 'rejected: Endurain ingestion job failed (%s)\n' "$error_code" >"$marker"
            err "REJECTED (ingestion job failed: $error_code): $base"
            upload_outcome='rejected'
            ;;
          *)
            err "TRANSIENT (ingestion job failed: ${error_code:-unknown}; check the server job before retrying): $base"
            upload_outcome='transient'
            ;;
        esac
        return 0
        ;;
      pending | processing | queued | running)
        sleep "$UPLOAD_POLL_SECONDS"
        ;;
      *)
        err "TRANSIENT (unexpected ingestion job status), will retry: $base"
        upload_outcome='transient'
        return 0
        ;;
    esac
  done

  err "TRANSIENT (ingestion job still pending after $((UPLOAD_POLL_ATTEMPTS * UPLOAD_POLL_SECONDS))s), will retry: $base"
  upload_outcome='transient'
}

upload_file() {
  local host="$1"
  local token="$2"
  local upload_path="$3"
  local base="$4"
  local marker="$5"
  local resp
  local code
  local body
  local job_id

  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H @<(printf 'Authorization: Bearer %s\n' "$token") \
      -H 'X-Client-Type: mobile' \
      -H "Idempotency-Key: ${marker##*/}" \
      -F "file=@$upload_path;filename=$base" \
      "https://$host/api/v1/activities/upload"
  )" || code='000'
  if [[ "$code" == '202' ]]
  then
    job_id="$(jq -er '.id' <"$resp")" || job_id=''
  fi
  body="$(head -c 300 "$resp")"
  rm -f "$resp"

  upload_outcome='transient'

  case "$code" in
    202)
      if [[ -z "$job_id" ]]
      then
        err "TRANSIENT (upload response had no job id), will retry: $base"
        return 0
      fi
      poll_upload "$host" "$token" "$job_id" "$base" "$marker"
      ;;
    400 | 413 | 415 | 422)
      # The file itself is unacceptable (e.g. a GPX with no track segments).
      # Record it as handled so we do not retry it forever.
      printf 'rejected HTTP %s: %s\n' "$code" "$base" >"$marker"
      err "REJECTED (HTTP $code): $base: $body"
      upload_outcome='rejected'
      ;;
    *)
      # Auth/rate-limit/server/network error: leave unmarked to retry later.
      err "TRANSIENT (HTTP $code), will retry: $base: $body"
      ;;
  esac
}

main() {
  local host="${ENDURAIN_HOST:?}"
  local watch_dir="${ENDURAIN_WATCH_DIR:?}"
  local state_dir="${ENDURAIN_STATE_DIR:?}"
  local token
  local f
  local base
  local marker
  local upload_path
  local uploaded=0
  local duplicate=0
  local rejected=0
  local transient=0
  local attempt

  : "${ENDURAIN_USERNAME:?}"
  : "${ENDURAIN_PASSWORD:?}"

  mkdir -p "$state_dir"

  collect_todo "$watch_dir" "$state_dir"
  for (( attempt = 1; attempt <= EMPTY_SCAN_RETRIES && ${#todo[@]} == 0; attempt++ ))
  do
    log "endurain-ingest: empty scan; retrying in ${EMPTY_SCAN_RETRY_SECONDS}s ($attempt/$EMPTY_SCAN_RETRIES)"
    sleep "$EMPTY_SCAN_RETRY_SECONDS"
    collect_todo "$watch_dir" "$state_dir"
  done

  if [[ "${#todo[@]}" -eq 0 ]]
  then
    log 'endurain-ingest: nothing new'
    return 0
  fi

  token="$(login "$host")"

  for f in "${todo[@]}"
  do
    base="$(basename "$f")"
    marker="$state_dir/${todo_hash[$f]}"

    check_duplicate "$f" "$host" "$token"
    if [[ -n "$is_duplicate" ]]
    then
      printf 'duplicate: activity within %ss of an existing one\n' "$DEDUP_WINDOW_SECONDS" >"$marker"
      log "DUPLICATE (skipped): $base"
      duplicate=$((duplicate + 1))
      continue
    fi

    rewrite_gpx_type "$f"
    upload_path="$f"
    if [[ -n "$rewritten_path" ]]
    then
      upload_path="$rewritten_path"
    fi

    fix_gpx_spikes "$upload_path"
    if [[ -n "$despiked_path" ]]
    then
      upload_path="$despiked_path"
    fi

    upload_file "$host" "$token" "$upload_path" "$base" "$marker"

    if [[ -n "$rewritten_path" ]]
    then
      rm -f "$rewritten_path"
    fi
    if [[ -n "$despiked_path" ]]
    then
      rm -f "$despiked_path"
    fi

    case "$upload_outcome" in
      uploaded)
        uploaded=$((uploaded + 1))
        ;;
      rejected)
        rejected=$((rejected + 1))
        ;;
      *)
        transient=$((transient + 1))
        ;;
    esac
  done

  log "endurain-ingest: uploaded=$uploaded duplicate=$duplicate rejected=$rejected transient=$transient"

  # Only signal failure for transient problems; permanently rejected/duplicate
  # files are recorded and must not keep the unit flapping.
  [[ "$transient" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
