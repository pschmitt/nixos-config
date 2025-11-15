#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--patch] TARGET_HOST"
}

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

while [[ -n "$*" ]]
do
  case "$1" in
    help|h|-h|--help)
      usage
      exit 0
      ;;
    -p|--patch)
      PATCH=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

TARGET_HOST="$1"

if [[ -z $TARGET_HOST ]]
then
  usage
  exit 2
fi

DATA=$(./tofu.sh output -json)

IFS=$'\t' read -r RESTIC_BUCKET_URL AWS_ACCESS_KEY_ID \
AWS_SECRET_ACCESS_KEY HEALTHCHECK_URL < <(
  jq -er --arg host "$TARGET_HOST" <<< "$DATA" '
      .bucket_urls.value as $urls
    | .access_key_ids.value as $ids
    | .access_key_secrets.value as $secrets
    | .restic_backup_ping_urls.value as $hc_urls

    | [("s3:" + $urls[$host]), $ids[$host], $secrets[$host], $hc_urls[$host]]
    | @tsv
  '
)

if [[ -z $RESTIC_BUCKET_URL || -z $AWS_ACCESS_KEY_ID || \
      -z $AWS_SECRET_ACCESS_KEY || -z $HEALTHCHECK_URL ]]
then
  echo "Error: Missing required Restic environment settings for host '$TARGET_HOST'" >&2
  exit 3
fi

RESTIC_ENV=$(
  echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
  echo "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
  echo "HEALTHCHECK_URL=$HEALTHCHECK_URL"
)

jq::to-string() {
  # NOTE don't use -r here!
  jq -en --arg v "$1" '$v'
}

if [[ -n $PATCH ]]
then
  set -euo pipefail

  SOPS_FILE=$(readlink -f "../hosts/${TARGET_HOST}/secrets.sops.yaml") || exit 1
  echo "Patching $SOPS_FILE"

  RESTIC_BUCKET_URL_JSON=$(jq::to-string "$RESTIC_BUCKET_URL")
  sops set "$SOPS_FILE" '["restic"]["repository"]' "$RESTIC_BUCKET_URL_JSON"

  RESTIC_ENV_JSON=$(jq::to-string "$RESTIC_ENV")
  sops set "$SOPS_FILE" '["restic"]["env"]' "$RESTIC_ENV_JSON"

  exit "$?"
fi

# Default: output to stdout
echo "Restic Bucket URL: $RESTIC_BUCKET_URL"
echo "$RESTIC_ENV"
