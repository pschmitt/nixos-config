#!/usr/bin/env bash

set -euo pipefail

RPC_URL="${MONEROD_RPC_URL_DEFAULT:-http://127.0.0.1:18081/get_info}"
THRESHOLD_BP="${MONEROD_THRESHOLD_BP_DEFAULT:-9000}"
OUTPUT_JSON=""
RPC_USERNAME="${MONEROD_RPC_USERNAME_DEFAULT:-}"
RPC_PASSWORD="${MONEROD_RPC_PASSWORD_DEFAULT:-}"
RPC_USERNAME_FILE="${MONEROD_RPC_USERNAME_FILE_DEFAULT:-}"
RPC_PASSWORD_FILE="${MONEROD_RPC_PASSWORD_FILE_DEFAULT:-}"

usage() {
  cat <<'EOF'
monerod-sync-status: Print monerod sync status (from /get_info)

Usage:
  monerod-sync-status [--json] [--threshold-bp N] [--rpc-url URL]

Flags:
  --json             Output JSON
  --threshold-bp N   Threshold in basis points (default: 9000 = 90.00%)
  --rpc-url URL      RPC URL to query (default: http://127.0.0.1:18081/get_info)
  -h, --help         Show this help
EOF
}

parse_cli_args() {
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      --json)
        OUTPUT_JSON=1
        shift
        ;;
      --threshold-bp)
        if [[ $# -lt 2 ]]
        then
          echo "Missing value for --threshold-bp" >&2
          return 2
        fi
        THRESHOLD_BP="$2"
        shift 2
        ;;
      --rpc-url)
        if [[ $# -lt 2 ]]
        then
          echo "Missing value for --rpc-url" >&2
          return 2
        fi
        RPC_URL="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        return 2
        ;;
    esac
  done

  if [[ -z "$THRESHOLD_BP" || -z "$RPC_URL" ]]
  then
    usage >&2
    return 2
  fi
}

fetch_monerod_get_info() {
  if [[ -n "${RPC_USERNAME:-}" && -z "${RPC_PASSWORD:-}" ]]
  then
    echo "RPC username is set but RPC password is missing" >&2
    return 2
  fi
  if [[ -z "${RPC_USERNAME:-}" && -n "${RPC_PASSWORD:-}" ]]
  then
    echo "RPC password is set but RPC username is missing" >&2
    return 2
  fi

  if [[ -z "${RPC_USERNAME:-}" && -n "${RPC_USERNAME_FILE:-}" ]]
  then
    RPC_USERNAME="$(head -n1 "$RPC_USERNAME_FILE")"
  fi
  if [[ -z "${RPC_PASSWORD:-}" && -n "${RPC_PASSWORD_FILE:-}" ]]
  then
    RPC_PASSWORD="$(head -n1 "$RPC_PASSWORD_FILE")"
  fi

  if [[ -n "${RPC_USERNAME:-}" && -z "${RPC_PASSWORD:-}" ]]
  then
    echo "RPC username file is set but RPC password is missing" >&2
    return 2
  fi
  if [[ -z "${RPC_USERNAME:-}" && -n "${RPC_PASSWORD:-}" ]]
  then
    echo "RPC password file is set but RPC username is missing" >&2
    return 2
  fi

  local curl_args=(
    -sS
    --fail
    --max-time 15
  )

  if [[ -n "${RPC_USERNAME:-}" && -n "${RPC_PASSWORD:-}" ]]
  then
    curl_args+=(--digest --user "${RPC_USERNAME}:${RPC_PASSWORD}")
  fi

  curl "${curl_args[@]}" "$RPC_URL"
}

get_info_json_to_status_tsv() {
  local info="$1"
  # shellcheck disable=SC2016
  jq -er '
    if (.target_height // 0) > 0
    then
      ((.height * 10000) / .target_height | floor) as $bp
      | [$bp, (.height // 0), (.target_height // 0)]
      | @tsv
    else
      [-1, (.height // 0), 0]
      | @tsv
    end
  ' <<<"$info"
}

print_status_json() {
  local exit_status="$1"
  local sync_bp="$2"
  local height="$3"
  local target_height="$4"
  local sync_percent="$5"

  local ok=""
  if [[ "$exit_status" -eq 0 ]]
  then
    ok=1
  fi

  # shellcheck disable=SC2016
  jq -n \
    --arg rpc_url "$RPC_URL" \
    --argjson threshold_bp "$THRESHOLD_BP" \
    --arg ok_present "${ok-}" \
    --argjson sync_bp "$sync_bp" \
    --arg sync_percent "$sync_percent" \
    --argjson height "$height" \
    --argjson target_height "$target_height" \
    '
      {
        ok: ($ok_present != ""),
        rpc_url: $rpc_url,
        threshold_bp: $threshold_bp,
        sync_bp: $sync_bp,
        sync_percent: (if $sync_percent == "" then null else ($sync_percent | tonumber) end),
        height: $height,
        target_height: $target_height
      }
    '
}

print_status_text() {
  local sync_bp="$1"
  local height="$2"
  local target_height="$3"

  if [[ "$target_height" -gt 0 ]]
  then
    printf "sync=%d.%02d%% height=%s target=%s\n" \
      "$((sync_bp / 100))" \
      "$((sync_bp % 100))" \
      "$height" \
      "$target_height"
  else
    printf 'sync=unknown height=%s target=%s\n' "$height" "$target_height"
  fi
}

main() {
  parse_cli_args "$@"

  local info
  info="$(fetch_monerod_get_info)"

  local line
  line="$(get_info_json_to_status_tsv "$info")"

  local sync_bp height target_height
  IFS=$'\t' read -r sync_bp height target_height <<< "$line"

  local rc=0
  if [[ "$target_height" -le 0 || "$sync_bp" -lt "$THRESHOLD_BP" ]]
  then
    rc=1
  fi

  if [[ -n "${OUTPUT_JSON:-}" ]]
  then
    local sync_percent=""
    if [[ "$sync_bp" -ge 0 ]]
    then
      sync_percent="$(printf '%d.%02d' "$((sync_bp / 100))" "$((sync_bp % 100))")"
    fi
    print_status_json "$rc" "$sync_bp" "$height" "$target_height" "$sync_percent"
  else
    print_status_text "$sync_bp" "$height" "$target_height"
  fi

  [[ "$rc" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
