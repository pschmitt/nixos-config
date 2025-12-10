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
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

  local git_root
  if [[ -n "${GIT_ROOT:-}" ]]
  then
    git_root="$GIT_ROOT"
  else
    git_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)

    if [[ -z "$git_root" ]]
    then
      git_root=$(git -C . rev-parse --show-toplevel 2>/dev/null || true)
    fi

    if [[ -z "$git_root" && -f "flake.nix" ]]
    then
      git_root=$(pwd)
    fi
  fi

  local sources_json

  if [[ -n $git_root ]]
  then
    if [[ "${script_dir}/" == "${git_root}/"* ]]
    then
      local relative_script_dir=${script_dir#"$git_root"/}
      sources_json="${SOURCES_JSON_PATH:-$git_root/$relative_script_dir/sources.json}"
    else
      sources_json="${SOURCES_JSON_PATH:-$git_root/pkgs/oci/oracle-cloud-agent/sources.json}"
    fi
  else
    if [[ "$script_dir" == /nix/store/* ]]
    then
       sources_json="${SOURCES_JSON_PATH:-./pkgs/oci/oracle-cloud-agent/sources.json}"
    else
       sources_json="${SOURCES_JSON_PATH:-$script_dir/sources.json}"
    fi
  fi

  if ! mkdir -p "$(dirname "$sources_json")" 2>/dev/null || ! touch "${sources_json}.tmp" 2>/dev/null
  then
    echo "Unable to write to ${sources_json}. Set SOURCES_JSON_PATH to a writable location." >&2
    exit 1
  fi
  rm -f "${sources_json}.tmp"

  local yum_repo="${YUM_REPO:-yum.eu-frankfurt-1.oci.oraclecloud.com}"
  local docker_run_timeout="${DOCKER_RUN_TIMEOUT:-300}"

  export YUM_REPO="$yum_repo" DOCKER_RUN_TIMEOUT="$docker_run_timeout"

  echo "Fetching oracle-cloud-agent download URLs (requires Docker/netbird connectivity)..." >&2
  local -a urls
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

  local aarch64_url x86_64_url
  for url in "${urls[@]}"
  do
    case "$url" in
      *aarch64*)
        aarch64_url="$url"
        ;;
      *x86_64*)
        x86_64_url="$url"
        ;;
    esac
  done

  if [[ -z ${aarch64_url:-} || -z ${x86_64_url:-} ]]
  then
    echo "Missing architecture-specific URLs" >&2
    exit 1
  fi

  local version release
  read -r version release <<<"$(parse_version_release "$x86_64_url")"

  echo "Prefetching hashes..." >&2
  local hash_aarch64 hash_x86_64
  hash_aarch64="$(prefetch_hash "$aarch64_url")"
  hash_x86_64="$(prefetch_hash "$x86_64_url")"

  jq -ner \
    --arg version "$version" \
    --arg release "$release" \
    --arg hashAarch64 "$hash_aarch64" \
    --arg hashX86_64 "$hash_x86_64" '
      {
        version: $version,
        release: $release,
        hashAarch64: $hashAarch64,
        hashX86_64: $hashX86_64
      }
  ' > "$sources_json"

  echo "Updated sources.json to version ${version}-${release}" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
