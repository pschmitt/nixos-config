STALWART_USER="$(<"$CREDENTIALS_DIRECTORY/username")"
STALWART_PASSWORD="$(<"$CREDENTIALS_DIRECTORY/password")"
export STALWART_USER STALWART_PASSWORD

unset STALWART_URL
while [[ -z "${STALWART_URL:-}" ]]; do
  for url in "$@"; do
    if curl --silent --fail --max-time 5 "$url/healthz/live" >/dev/null; then
      export STALWART_URL="$url"
      break
    fi
  done
  [[ -n "${STALWART_URL:-}" ]] || sleep 1
done

if ! stalwart-cli apply --file "$CREDENTIALS_DIRECTORY/plan" >/dev/null 2>&1; then
  echo "Stalwart rejected the provisioning plan" >&2
  exit 1
fi

if [[ "${STALWART_RELOAD_SETTINGS:-}" == 1 ]]; then
  if ! stalwart-cli create Action/ReloadSettings >/dev/null 2>&1; then
    echo "Stalwart rejected the settings reload" >&2
    exit 1
  fi
fi
