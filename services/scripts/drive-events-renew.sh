api() {
  local method="$1"
  local url="$2"
  shift 2

  curl -sS -X "$method" "$url" \
    -H "Authorization: Bearer $access_token" \
    -H "x-goog-user-project: $EVENTS_PROJECT" \
    -H 'Content-Type: application/json' \
    --write-out '\n%{http_code}' \
    "$@"
}

main() {
  local base
  local access_token
  local body
  local code
  local name
  local out
  local state

  base=https://workspaceevents.googleapis.com/v1

  access_token="$(
    curl -fsS https://oauth2.googleapis.com/token \
      -d client_id="$OAUTH_CLIENT_ID" \
      -d client_secret="$OAUTH_CLIENT_SECRET" \
      -d refresh_token="$OAUTH_REFRESH_TOKEN" \
      -d grant_type=refresh_token | jq -er .access_token
  )"

  body="$(jq -n \
    --arg target "//drive.googleapis.com/files/$EVENTS_FOLDER_ID" \
    --arg topic "projects/$EVENTS_PROJECT/topics/$EVENTS_TOPIC" \
    '{
      targetResource: $target,
      eventTypes: [
        "google.workspace.drive.file.v3.created",
        "google.workspace.drive.file.v3.moved",
        "google.workspace.drive.file.v3.contentChanged"
      ],
      driveOptions: { includeDescendants: true },
      notificationEndpoint: { pubsubTopic: $topic },
      payloadOptions: { includeResource: false }
    }')"

  # There is at most one subscription per folder and user: look it up by
  # target, renew it if present and create it otherwise.
  out="$(api GET "$base/subscriptions" -G \
    --data-urlencode 'filter=event_types:"google.workspace.drive.file.v3.created"')"
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [[ "$code" != 200 ]]
  then
    printf 'Listing subscriptions failed (HTTP %s): %s\n' "$code" "$out" >&2
    return 1
  fi

  name="$(jq -r --arg target "//drive.googleapis.com/files/$EVENTS_FOLDER_ID" \
    '[.subscriptions[]? | select(.targetResource == $target) | .name][0] // empty' <<< "$out")"

  if [[ -z "$name" ]]
  then
    out="$(api POST "$base/subscriptions" -d "$body")"
    code="${out##*$'\n'}"
    out="${out%$'\n'*}"
    if [[ "$code" != 200 ]]
    then
      printf 'Creating subscription failed (HTTP %s): %s\n' "$code" "$out" >&2
      return 1
    fi

    printf 'Created subscription (expires %s)\n' \
      "$(jq -r '.response.expireTime // "?"' <<< "$out")"
    return 0
  fi

  out="$(api GET "$base/$name")"
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [[ "$code" != 200 ]]
  then
    printf 'Reading %s failed (HTTP %s): %s\n' "$name" "$code" "$out" >&2
    return 1
  fi

  state="$(jq -r .state <<< "$out")"
  if [[ "$state" != ACTIVE ]]
  then
    printf 'Subscription is %s, reactivating\n' "$state" >&2
    out="$(api POST "$base/$name:reactivate" -d '{}')"
    code="${out##*$'\n'}"
    if [[ "$code" != 200 ]]
    then
      printf 'Reactivating failed (HTTP %s): %s\n' "$code" "${out%$'\n'*}" >&2
      return 1
    fi
  fi

  # ttl of 0s requests the maximum lifetime
  out="$(api PATCH "$base/$name?updateMask=ttl" -d '{"ttl":"0s"}')"
  code="${out##*$'\n'}"
  out="${out%$'\n'*}"
  if [[ "$code" != 200 ]]
  then
    printf 'Renewing failed (HTTP %s): %s\n' "$code" "$out" >&2
    return 1
  fi

  printf 'Renewed subscription (expires %s)\n' \
    "$(jq -r '.response.expireTime // .expireTime // "?"' <<< "$out")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
