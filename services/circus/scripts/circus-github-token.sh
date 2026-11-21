#!/usr/bin/env bash
# Mint a GitHub App installation token (valid one hour) for Circus' commit
# statuses and write it atomically to OUT_FILE. On any failure the previous
# token stays in place and the script exits non-zero. Neither the App key, the
# JWT nor the token ever reach the command line or the log.

usage() {
  cat <<EOF
Usage: $(basename "$0") APP_ID_FILE PRIVATE_KEY_FILE OWNER/REPO OUT_FILE NIX_CONFIG_FILE AUTH_REPOSITORIES_JSON

Look up the App's installation on OWNER/REPO and write a fresh installation
token to OUT_FILE and a Nix extra-access-tokens config to NIX_CONFIG_FILE
(both mode 0440, group of their directory).
EOF
}

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# RS256 JWT for the App, valid for 10 minutes (iat backdated against clock skew).
app_jwt() {
  local app_id="$1"
  local key_file="$2"
  local now
  local header
  local payload
  local signature

  now="$(date +%s)" || return 1
  # printf, not a here-string: a trailing newline would corrupt the JWT.
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)" || return 1
  payload="$(
    printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$app_id" | b64url
  )" || return 1
  signature="$(
    printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key_file" -binary | b64url
  )" || return 1
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

github_api() {
  local auth_file="$1"
  shift

  curl --fail --silent --show-error --max-time 30 \
    --header @"$auth_file" \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    "$@"
}

mint() {
  local app_id_file="$1"
  local key_file="$2"
  local repo="$3"
  local out_file="$4"
  local nix_config_file="$5"
  local repositories_json="$6"
  local work_dir="$7"
  local app_id
  local jwt
  local installation_id
  local owner
  local repo_names
  local nix_prefixes
  local token

  app_id="$(tr -d '[:space:]' < "$app_id_file")" || return 1
  if [[ ! "$app_id" =~ ^[0-9]+$ ]]
  then
    printf 'App id in %s is not numeric\n' "$app_id_file" >&2
    return 1
  fi

  jwt="$(app_jwt "$app_id" "$key_file")" || return 1
  printf 'Authorization: Bearer %s\n' "$jwt" > "$work_dir/app-auth" || return 1

  github_api "$work_dir/app-auth" \
    "https://api.github.com/repos/${repo}/installation" > "$work_dir/installation" || return 1
  installation_id="$(jq -r '.id' "$work_dir/installation")" || return 1
  if [[ ! "$installation_id" =~ ^[0-9]+$ ]]
  then
    printf 'No installation of App %s on %s\n' "$app_id" "$repo" >&2
    return 1
  fi

  github_api "$work_dir/app-auth" --request POST \
    "https://api.github.com/app/installations/${installation_id}/access_tokens" \
    > "$work_dir/response" || return 1
  jq -er '.token' "$work_dir/response" > "$work_dir/token" || return 1
  if [[ ! -s "$work_dir/token" ]]
  then
    printf 'GitHub returned an empty token\n' >&2
    return 1
  fi

  chmod 0440 "$work_dir/token" || return 1
  chgrp --reference="$(dirname "$out_file")" "$work_dir/token" || return 1
  mv -f "$work_dir/token" "$out_file" || return 1

  owner="${repo%%/*}"
  if [[ "$repo" != */* || -z "$owner" ]]
  then
    printf 'App repository must be OWNER/REPO\n' >&2
    return 1
  fi

  if ! jq -e --arg owner "$owner" 'type == "array" and all(.[]; type == "string" and (split("/") | length == 2) and (split("/")[0] == $owner) and (split("/")[1] != ""))' \
    <<<"$repositories_json" >/dev/null
  then
    printf 'Nix auth repositories must be OWNER/REPO entries under %s\n' "$owner" >&2
    return 1
  fi

  repo_names="$(jq -c --arg owner "$owner" '[.[] | split("/")[1]]' <<<"$repositories_json")" || return 1
  nix_prefixes="$(jq -r '[.[] | "github.com/" + .] | join(" ")' <<<"$repositories_json")" || return 1
  if [[ "$repositories_json" != '[]' ]]
  then
    github_api "$work_dir/app-auth" --request POST \
      --data "$(jq -cn --argjson repositories "$repo_names" '{repositories: $repositories, permissions: {contents: "read"}}')" \
      "https://api.github.com/app/installations/${installation_id}/access_tokens" \
      > "$work_dir/nix-response" || return 1
    jq -er '.token' "$work_dir/nix-response" > "$work_dir/nix-token" || return 1
    if [[ ! -s "$work_dir/nix-token" ]]
    then
      printf 'GitHub returned an empty scoped Nix token\n' >&2
      return 1
    fi

    # Scoped archive reads use their own token; the broader notification token
    # was atomically published above so this failure cannot block statuses.
    token="$(<"$work_dir/nix-token")" || return 1
    printf 'extra-access-tokens = %s\n' \
      "$(jq -nr --arg prefixes "$nix_prefixes" --arg token "$token" '$prefixes | split(" ") | map(. + "=" + $token) | join(" ")')" \
      > "$work_dir/nix-extra.conf" || return 1
    unset token
  else
    : > "$work_dir/nix-extra.conf" || return 1
  fi

  chmod 0440 "$work_dir/nix-extra.conf" || return 1
  chgrp --reference="$(dirname "$nix_config_file")" "$work_dir/nix-extra.conf" || return 1
  mv -f "$work_dir/nix-extra.conf" "$nix_config_file" || return 1

  printf 'Minted an installation token for %s (installation %s), expires %s\n' \
    "$repo" "$installation_id" "$(jq -r '.expires_at' "$work_dir/response")"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac

  if [[ $# -ne 6 ]]
  then
    usage >&2
    return 2
  fi

  local out_dir
  local work_dir
  local rc

  out_dir="$(dirname "$4")"
  # Next to OUT_FILE, so the final mv is an atomic rename on one filesystem.
  work_dir="$(mktemp -d "$out_dir/.mint.XXXXXX")" || return 1
  chmod 0700 "$work_dir" || return 1

  rc=0
  mint "$@" "$work_dir" || rc=$?
  rm -rf -- "$work_dir"
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
