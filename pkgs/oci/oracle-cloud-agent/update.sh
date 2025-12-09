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

  cd "$script_dir"

  yum_repo="${YUM_REPO:-yum.eu-frankfurt-1.oci.oraclecloud.com}"
  docker_run_timeout="${DOCKER_RUN_TIMEOUT:-300}"

  export YUM_REPO="$yum_repo" DOCKER_RUN_TIMEOUT="$docker_run_timeout"

  echo "Fetching oracle-cloud-agent download URLs (requires Docker/netbird connectivity)..." >&2
  mapfile -t urls < <(
    ./get-download-urls.sh |
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

  cat >"$script_dir/sources.json" <<EOF
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
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
  main "$@"
fi
