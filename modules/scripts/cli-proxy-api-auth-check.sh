# Usage: cli-proxy-api-auth-check BASE_URL MANAGEMENT_KEY_FILE
#
# Exit 1 when an enabled CLIProxyAPI account needs a new login or has any other
# authentication problem. Rate limits and quota cooldowns are not auth problems.
base_url=${1:?base URL required}
key_file=${2:?management key file required}

auth_error='unauthori[sz]ed|authentication|invalid[_ -]?(grant|token|api[_ -]?key)|refresh|re-?login|log ?in|revoked|forbidden|permission_error|expired'

if ! response=$(
  curl --silent --show-error --fail --max-time 20 \
    --config <(printf 'header = "Authorization: Bearer %s"\n' "$(<"$key_file")") \
    "${base_url%/}/v0/management/auth-files"
); then
  echo "🚨 Unable to query the CLIProxyAPI management API"
  exit 1
fi

problems=$(
  jq -r --arg re "$auth_error" '
    .files[]
    | select(.disabled != true)
    | select(
        (.status == "error" or .unavailable == true)
        and (
          ((.status_message // "") | test($re; "i"))
          or any(.cooldowns[]?; .http_status == 401 or .http_status == 403)
        )
      )
    | "\(.provider): \(.email // .name) (\(.status))"
  ' <<<"$response"
)

if [[ -n $problems ]]
then
  echo "🚨 CLIProxyAPI accounts with authentication problems:"
  echo "$problems"
  exit 1
fi

echo "✅ All enabled CLIProxyAPI accounts are authenticated"
