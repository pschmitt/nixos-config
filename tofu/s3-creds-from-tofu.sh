#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

./tofu.sh output -json 2>/dev/null | jq -er --arg host "$1" '
  .access_key_ids.value as $ids
  | .access_key_secrets.value as $secrets

  | if $host != "" and $host != null and $ids[$host] != null
    then
      # Show host keys only
      "\($ids[$host]) \($secrets[$host])"
    else
      # Show all
      ($ids | keys_unsorted[]) as $h
      | "\($h): \($ids[$h]) \($secrets[$h])"
    end
'
