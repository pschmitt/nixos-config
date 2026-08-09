# shellcheck shell=bash
api_key_file="${CREDENTIALS_DIRECTORY}/api-key"
export STALWART_URL="http://127.0.0.1:8080"
stalwart_token="$(< "$api_key_file")"
export STALWART_TOKEN="$stalwart_token"

today="$(date -u +%F)"
domains_json="$(stalwart-cli query Domain --fields id,name,dnsManagement --json)"
tasks_json="$(stalwart-cli query Task --where @type=DnsManagement --fields domainId,status --json | jq -s '.')"

while IFS=$'\t' read -r domain_id domain_name update_records
do
  if [[ -z "$domain_id" || -z "$domain_name" || -z "$update_records" ]]
  then
    continue
  fi

  if [[ "$update_records" == "[]" ]]
  then
    printf 'Skipping %s: no DNS record types are enabled for publication\n' "$domain_name"
    continue
  fi

  if jq -e --arg domain_id "$domain_id" --arg today "$today" '
    any(.[];
      .domainId == $domain_id
      and (
        .status."@type" == "Pending"
        or .status."@type" == "Retry"
        or ((.status.createdAt // "") | startswith($today))
      )
    )
  ' <<<"$tasks_json" >/dev/null
  then
    printf 'Skipping %s: DNS task already active or created today\n' "$domain_name"
    continue
  fi

  printf 'Creating DNS reconciliation task for %s\n' "$domain_name"
  stalwart-cli create Task/DnsManagement \
    --field "domainId=$domain_id" \
    --field "updateRecords=$update_records" \
    --no-color
done < <(
  jq -r '
    select(.dnsManagement."@type" == "Automatic")
    | [
        .id,
        .name,
        (.dnsManagement.publishRecords // {}
          | to_entries
          | map(select(.value == true) | .key)
          | @json)
      ]
    | @tsv
  ' <<<"$domains_json"
)
