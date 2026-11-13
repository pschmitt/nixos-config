# Usage: cli-proxy-api-auth-check BASE_URL MANAGEMENT_KEY_FILE
#
# Exit 1 when a CLIProxyAPI account needs a new login. Uses the v8 credentials
# endpoint, whose `requires_sign_in`, `next_action` and `renewal_state` fields
# are CLIProxyAPI's own verdict that a refresh token was rejected for good.
# Rate limits and quota cooldowns do not set them.
#
# Credentials the user disabled are ignored, except those CLIProxyAPI itself
# disabled after an invalid grant ("disabled (invalid grant)").
base_url=${1:?base URL required}
key_file=${2:?management key file required}

if ! response=$(
  curl --silent --show-error --fail --max-time 20 \
    --config <(printf 'header = "Authorization: Bearer %s"\n' "$(<"$key_file")") \
    "${base_url%/}/v8/management/credentials"
); then
  echo "🚨 Unable to query the CLIProxyAPI management API"
  exit 1
fi

problems=$(
  jq -r '
    def sign_in:
      .requires_sign_in == true
      or .next_action == "sign_in"
      or (.renewal_state | IN("sign_in_required", "expired_sign_in_required"))
      or .recovery_stage == "sign_in_required"
      or ((.status_message // "") | test("unauthorized|invalid[_ ]grant"; "i"))
      or any(.cooldowns[]?; .http_status == 401);

    .files[]
    | select(
        (.disabled != true and sign_in)
        or ((.status_message // "") | test("invalid[_ ]grant"; "i"))
      )
    | "\(.provider): \(.email // .name) (\(.status_message // .renewal_state))"
  ' <<<"$response"
)

if [[ -n $problems ]]
then
  echo "🚨 CLIProxyAPI accounts that need a new login:"
  echo "$problems"
  exit 1
fi

echo "✅ All enabled CLIProxyAPI accounts are authenticated"
