{ config, pkgs, ... }:
let
  stashScan = pkgs.writeShellScript "stash-scan" ''
    STASH_HOST="$(cat "$STASH_HOST_FILE")"
    STASH_API_KEY="$(cat "$STASH_API_KEY_FILE")"

    curl_stash_api() {
      local body="$1"
      ${pkgs.curl}/bin/curl \
        -fsS \
        --retry 3 \
        --retry-delay 1 \
        --retry-all-errors \
        --retry-connrefused \
        --connect-timeout 5 \
        --max-time 300 \
        -H "ApiKey: $STASH_API_KEY" \
        --json "$body" \
        "''${STASH_HOST}/graphql"
    }

    stash_mutation() {
      local mutation="$1"
      local flag="$2"
      local no_input=false

      if [[ "$flag" == "no-input" ]]
      then
        no_input=true
      else
        no_input=false
      fi

      local request
      request=$(${pkgs.jq}/bin/jq -n \
        --arg m "$mutation" \
        --argjson no_input "$no_input" '
          if $no_input
          then {query: ("mutation { \($m) }")}
          else {query: ("mutation { \($m)(input:{}) }")}
          end
        ')

      echo "==> Running $mutation (no_input=$no_input)"

      # Capture response so we can surface GraphQL errors (HTTP 200)
      local resp
      if ! resp="$(curl_stash_api "$request")"
      then
        echo "HTTP failure while calling $mutation" >&2
        return 0
      fi

      # Log GraphQL errors but keep going
      if ${pkgs.jq}/bin/jq -e '.errors' >/dev/null 2>&1 <<<"$resp"
      then
        echo "GraphQL errors from $mutation:" >&2
        ${pkgs.jq}/bin/jq -r '.errors[] | "- \(.message)"' <<<"$resp" >&2
      fi

      # Optional: print job id for visibility
      ${pkgs.jq}/bin/jq -r '.data | to_entries[0] | "queued \(.key) → id \(.value)"' <<<"$resp" 2>/dev/null || true
    }

    MUTATIONS=(
      metadataScan
      metadataIdentify
      metadataAutoTag
      metadataGenerate
      metadataClean:no-input
      metadataCleanGenerated
      optimiseDatabase:no-input
      # backupDatabase
    )

    # set -x
    for ITEM in "''${MUTATIONS[@]}"
    do
      IFS=":" read -r NAME FLAG <<<"$ITEM"
      stash_mutation "$NAME" "$FLAG"
    done
  '';
in
{
  sops.secrets."stash/api-key" = {
    inherit (config.custom) sopsFile;
  };
  sops.secrets."stash/host" = {
    inherit (config.custom) sopsFile;
  };

  systemd.services.stash-scan = {
    description = "Stash: metadata scan + generate";
    environment = {
      STASH_HOST_FILE = config.sops.secrets."stash/host".path;
      STASH_API_KEY_FILE = config.sops.secrets."stash/api-key".path;
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = stashScan;
    };
  };

  systemd.timers.stash-scan = {
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "6h";
      Persistent = true;
    };
  };
}
