#!/usr/bin/env bash
set -euo pipefail

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-}"
HOSTS="${HOSTS:-}"

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]
then
  echo "BASE_SHA and HEAD_SHA must be set" >&2
  exit 1
fi

MAX_LINES="${MAX_LINES:-200}"

cleanup() {
  if [[ -n "${BASE_WORKTREE:-}" ]]
  then
    git worktree remove "$BASE_WORKTREE" --force
  fi
}
trap cleanup EXIT

discover_hosts() {
  if [[ -n "$HOSTS" ]]
  then
    # Space-separated hostnames: "ge2 gk4 x13"
    read -r -a _hosts <<<"$HOSTS"
    printf '%s\n' "${_hosts[@]}"
    return 0
  fi

  # Discover hosts dynamically, instead of hardcoding.
  # Use the intersection between base and head to avoid noisy "missing attr" failures.
  local head_json base_json

  head_json="$(nix flake show --json 2>/dev/null)"
  base_json="$(cd "$BASE_WORKTREE" && nix flake show --json 2>/dev/null)"

  comm -12 \
    <(jq -r '.nixosConfigurations | keys[]' <<<"$head_json" | sort -u) \
    <(jq -r '.nixosConfigurations | keys[]' <<<"$base_json" | sort -u)
}

BASE_WORKTREE="$(mktemp -d)"
git worktree add "$BASE_WORKTREE" "$BASE_SHA" >/dev/null

nvd_store_path="$(nix build --no-link --print-out-paths nixpkgs#nvd)"
nvd_bin="$nvd_store_path/bin/nvd"

build_toplevel() {
  local flake_path="$1"
  local host="$2"

  nix build --no-link --print-out-paths "${flake_path}#nixosConfigurations.${host}.config.system.build.toplevel"
}

trim_output() {
  local output="$1"
  local max_lines="$2"
  local line_count

  line_count="$(printf "%s\n" "$output" | wc -l | tr -d ' ')"
  if (( line_count > max_lines ))
  then
    printf "%s\n" "$output" | sed -n "1,${max_lines}p"
    printf "%s\n" "... truncated to ${max_lines} lines"
    return 0
  fi

  printf "%s" "$output"
}

printf '%s\n' '<!-- flake-lock-diff -->'
printf '%s\n' '## Flake lock update: per-host diffs'
printf '\n'
printf 'Base: %s\n' "$BASE_SHA"
printf '\n'
printf 'Head: %s\n' "$HEAD_SHA"
printf '\n'

mapfile -t hosts < <(discover_hosts)
if (( ${#hosts[@]} == 0 ))
then
  printf '%s\n' 'No shared hosts found between base and head flake.'
  exit 0
fi

for host in "${hosts[@]}"
do
  printf '### %s\n' "$host"
  printf '\n'

  if ! base_out="$(build_toplevel "$BASE_WORKTREE" "$host" 2>/dev/null)"
  then
    printf '%s\n' 'Build failed for base revision.'
    printf '\n'
    continue
  fi

  if ! head_out="$(build_toplevel "." "$host" 2>/dev/null)"
  then
    printf '%s\n' 'Build failed for head revision.'
    printf '\n'
    continue
  fi

  diff_output="$("$nvd_bin" diff "$base_out" "$head_out" 2>/dev/null || true)"
  if [[ -z "$diff_output" ]]
  then
    diff_output="(no output)"
  fi

  diff_output="$(trim_output "$diff_output" "$MAX_LINES")"

  printf '%s\n' '```'
  printf '%s\n' "$diff_output"
  printf '%s\n' '```'
  printf '\n'
done
