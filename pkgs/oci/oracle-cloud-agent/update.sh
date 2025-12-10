#!/usr/bin/env bash

set -euo pipefail

prefetch_hash() {
  local url="$1"

  nix store prefetch-file --json "$url" | jq -r '.hash'
}

parse_version_release() {
  local url="$1"

  python - "$url" <<'PY'
import re
import sys

url = sys.argv[1]
match = re.search(
    r"oracle-cloud-agent-([^-]+)-([^.]+\.el[0-9]+)\.x86_64\.rpm",
    url,
)
if not match:
    raise SystemExit(f"Unable to parse version/release from URL: {url}")

print(f"{match.group(1)} {match.group(2)}")
PY
}

main() {
  local repo_root
  local script_dir
  local relative_script_dir
  local sources_json
  local -a urls
  local aarch64_url
  local x86_64_url
  local version
  local release
  local hash_aarch64
  local hash_x86_64
  local yum_repo
  local docker_run_timeout

  if [[ -f /etc/profile.d/nix.sh ]]
  then
    # shellcheck disable=SC1091
    source /etc/profile.d/nix.sh
  fi

  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  repo_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)

  if [[ -n $repo_root ]]
  then
    if [[ "${script_dir}/" == "${repo_root}/"* ]]
    then
      relative_script_dir=${script_dir#"$repo_root"/}
      sources_json="${SOURCES_JSON_PATH:-$repo_root/$relative_script_dir/sources.json}"
    else
      sources_json="${SOURCES_JSON_PATH:-$script_dir/sources.json}"
    fi
  else
    sources_json="${SOURCES_JSON_PATH:-$script_dir/sources.json}"
  fi

  if ! mkdir -p "$(dirname "$sources_json")" 2>/dev/null || ! touch "${sources_json}.tmp" 2>/dev/null
  then
    echo "Unable to write to ${sources_json}. Set SOURCES_JSON_PATH to a writable location." >&2
    exit 1
  fi
  rm -f "${sources_json}.tmp"

  yum_repo="${YUM_REPO:-yum.eu-frankfurt-1.oci.oraclecloud.com}"
  docker_run_timeout="${DOCKER_RUN_TIMEOUT:-300}"

  export YUM_REPO="$yum_repo" DOCKER_RUN_TIMEOUT="$docker_run_timeout"

  echo "Fetching oracle-cloud-agent download URLs (requires Docker/netbird connectivity)..." >&2
  mapfile -t urls < <(
    "$script_dir/get-download-urls.sh" |
      grep -Eo 'https?://[^[:space:]]*oracle-cloud-agent-[0-9][^[:space:]]*\.rpm' |
      sort -u
  )

  if [[ ${#urls[@]} -lt 2 ]]
  then
    echo "Failed to discover oracle-cloud-agent URLs" >&2
    exit 1
  fi

  for url in "${urls[@]}"
  do
    case "$url" in
      *aarch64.rpm)
        aarch64_url="$url"
        ;;
      *x86_64.rpm)
        x86_64_url="$url"
        ;;
    esac
  done

  if [[ -z ${aarch64_url:-} || -z ${x86_64_url:-} ]]
  then
    echo "Missing architecture-specific URLs" >&2
    exit 1
  fi

  read -r version release <<<"$(parse_version_release "$x86_64_url")"

  echo "Prefetching hashes..." >&2
  hash_aarch64="$(prefetch_hash "$aarch64_url")"
  hash_x86_64="$(prefetch_hash "$x86_64_url")"

  cat >"$sources_json" <<EOF
{
  "version": "${version}",
  "release": "${release}",
  "hashAarch64": "${hash_aarch64}",
  "hashX86_64": "${hash_x86_64}"
}
EOF

  echo "Updated sources.json to version ${version}-${release}" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
