# shellcheck shell=bash
# Upload new Gadgetbridge/OpenTracks activity files to Endurain.
# Wrapped by pkgs.writeShellApplication, which prepends the shebang and
# errexit/nounset/pipefail. Configuration comes from the environment, set by
# the systemd unit:
#   ENDURAIN_HOST, ENDURAIN_USERNAME, ENDURAIN_PASSWORD, ENDURAIN_TZ,
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
  local resp
  local code
  local token

  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H 'X-Client-Type: mobile' \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "username=$ENDURAIN_USERNAME" \
      --data-urlencode "password=$ENDURAIN_PASSWORD" \
      "https://$host/api/v1/auth/login"
  )" || code='000'

  if [[ "$code" != '200' ]]
  then
    err "login failed (HTTP $code)"
    rm -f "$resp"
    return 1
  fi

  if [[ "$(jq -r '.mfa_required // false' <"$resp")" == 'true' ]]
  then
    err 'login requires MFA; unattended ingest cannot proceed'
    rm -f "$resp"
    return 1
  fi

  if ! token="$(jq -er '.access_token' <"$resp")"
  then
    rm -f "$resp"
    return 1
  fi

  rm -f "$resp"
  printf '%s\n' "$token"
}

# Extract the "sub" claim (our own user id) from the access token's JWT
# payload, without verifying the signature - we already trust the connection
# to our own server, and the result is only used to scope a read-only lookup
# of our own recent activities.
jwt_sub() {
  local token="$1"
  local payload

  payload="$(cut -d. -f2 <<<"$token")"
  payload="${payload//-/+}"
  payload="${payload//_//}"
  case $(( ${#payload} % 4 )) in
    2) payload+='==' ;;
    3) payload+='=' ;;
  esac

  base64 -d <<<"$payload" 2>/dev/null | jq -r '.sub // empty'
}

# Print the start_time of our DEDUP_LOOKBACK most recent activities, one per
# line. Best-effort: prints nothing on any failure, which makes
# check_duplicate fail open (upload proceeds) rather than block ingestion on
# an API hiccup.
recent_start_times() {
  local host="$1"
  local token="$2"
  local user_id="$3"
  local resp
  local code

  if [[ -z "$user_id" ]]
  then
    return 0
  fi

  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H "Authorization: Bearer $token" \
      -H 'X-Client-Type: mobile' \
      "https://$host/api/v1/activities/user/$user_id/page_number/1/num_records/$DEDUP_LOOKBACK"
  )" || code='000'

  if [[ "$code" == '200' ]]
  then
    jq -r '.[].start_time' <"$resp"
  fi
  rm -f "$resp"
}

# Sets is_duplicate=1 when an activity already exists within
# DEDUP_WINDOW_SECONDS of this GPX's first trackpoint. Only .gpx is checked
# (the only format seen duplicated in practice) and start_time comparisons
# happen in epoch seconds: the GPX's own <time> is UTC, Endurain's returned
# start_time is local wall-clock time in $tz.
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
  local user_id="$4"
  local tz="$5"
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
    existing_epoch="$(TZ="$tz" date -d "$existing_start" +%s)" || continue
    delta=$(( existing_epoch - epoch ))
    if (( delta > -DEDUP_WINDOW_SECONDS && delta < DEDUP_WINDOW_SECONDS ))
    then
      is_duplicate=1
      return 0
    fi
  done < <(recent_start_times "$host" "$token" "$user_id")
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
upload_file() {
  local host="$1"
  local token="$2"
  local upload_path="$3"
  local base="$4"
  local marker="$5"
  local resp
  local code
  local body

  resp="$(mktemp)"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -H "Authorization: Bearer $token" \
      -H 'X-Client-Type: mobile' \
      -F "file=@$upload_path;filename=$base" \
      "https://$host/api/v1/activities/create/upload"
  )" || code='000'
  body="$(head -c 300 "$resp")"
  rm -f "$resp"

  upload_outcome='transient'

  case "$code" in
    201)
      : >"$marker"
      log "uploaded: $base"
      upload_outcome='uploaded'
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
  local tz="${ENDURAIN_TZ:?}"
  local watch_dir="${ENDURAIN_WATCH_DIR:?}"
  local state_dir="${ENDURAIN_STATE_DIR:?}"
  local token
  local user_id
  local f
  local base
  local marker
  local upload_path
  local uploaded=0
  local duplicate=0
  local rejected=0
  local transient=0

  : "${ENDURAIN_USERNAME:?}"
  : "${ENDURAIN_PASSWORD:?}"

  mkdir -p "$state_dir"

  collect_todo "$watch_dir" "$state_dir"
  if [[ "${#todo[@]}" -eq 0 ]]
  then
    log 'endurain-ingest: nothing new'
    return 0
  fi

  token="$(login "$host")"
  user_id="$(jwt_sub "$token")"

  for f in "${todo[@]}"
  do
    base="$(basename "$f")"
    marker="$state_dir/${todo_hash[$f]}"

    check_duplicate "$f" "$host" "$token" "$user_id" "$tz"
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
