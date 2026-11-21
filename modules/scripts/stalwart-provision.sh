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

required_fields="$CREDENTIALS_DIRECTORY/required-fields"
if [[ -f "$required_fields" ]]; then
  mapfile -t object_types < <(jq -r 'keys[]' "$required_fields")
  if ! stalwart-cli snapshot "${object_types[@]}" 2>/dev/null |
    jq -es --slurpfile required "$required_fields" --slurpfile plan "$CREDENTIALS_DIRECTORY/plan" '
      def objects($operations; $type):
        [$operations[] | select(.object == $type) |
          if .["@type"] == "update" then {key: "singleton", value: .value}
          else .value | to_entries[]
          end] | from_entries;

      . as $snapshot |
      all($required[0] | to_entries[];
        . as $check |
        objects($snapshot; $check.key) as $live |
        (objects($plan; $check.key) | keys) as $ids |
        ($ids | length > 0) and
        all($ids[];
          . as $id |
          all($check.value | to_entries[];
            . as $field |
            $live[$id][$field.key] == $field.value
          )
        )
      )
    ' >/dev/null 2>&1; then
    echo "Stalwart could not verify the required existing field values" >&2
    exit 1
  fi
fi

secret_args=()
for credential in "$CREDENTIALS_DIRECTORY"/plan-secret-*; do
  [[ -f "$credential" ]] || continue
  name="${credential##*/plan-secret-}"
  secret_args+=(--rawfile "$name" "$credential")
done
apply_plan="$(mktemp "$HOME/plan.XXXXXXXX")"
trap 'rm -- "$apply_plan"' EXIT
if ! jq -c "${secret_args[@]}" '
  walk(
    if type == "object" and has("$stalwartSecret") then
      $ARGS.named[."$stalwartSecret"] // error("Missing provisioning secret")
    elif type == "object" and has("$stalwartOrderedMap") then
      ."$stalwartOrderedMap" | map({key: .[0], value: .[1]}) | from_entries
    else .
    end
  )
' "$CREDENTIALS_DIRECTORY/plan" >"$apply_plan" 2>/dev/null; then
  echo "Stalwart could not render the provisioning plan" >&2
  exit 1
fi

if ! stalwart-cli apply --file "$apply_plan" >/dev/null 2>&1; then
  echo "Stalwart rejected the provisioning plan" >&2
  exit 1
fi

if [[ "${STALWART_RELOAD_SETTINGS:-}" == 1 ]]; then
  if ! stalwart-cli create Action/ReloadSettings >/dev/null 2>&1; then
    echo "Stalwart rejected the settings reload" >&2
    exit 1
  fi
fi
