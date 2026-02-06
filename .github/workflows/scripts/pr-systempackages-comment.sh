#!/usr/bin/env bash
set -euo pipefail

export NIXPKGS_ALLOW_UNFREE=1
export NIX_CONFIG="accept-flake-config = true${NIX_CONFIG:+ $NIX_CONFIG}"

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-}"
HOSTS="${HOSTS:-}"
MAX_LINES="${MAX_LINES:-400}"
INCLUDE_ISO="${INCLUDE_ISO:-1}"

if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]
then
  echo "BASE_SHA and HEAD_SHA must be set" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${BASE_WORKTREE:-}" ]]
  then
    git worktree remove "$BASE_WORKTREE" --force
  fi
}
trap cleanup EXIT

BASE_WORKTREE="$(mktemp -d)"
git worktree add "$BASE_WORKTREE" "$BASE_SHA" >/dev/null

changed_files() {
  git diff --name-only "$BASE_SHA" "$HEAD_SHA"
}

is_nix_related_change() {
  local file

  while IFS= read -r file
  do
    case "$file" in
      flake.nix|flake.lock|*.nix)
        return 0
        ;;
      common/*|hardware/*|home-manager/*|hosts/*|modules/*|overlays/*|pkgs/*|services/*|workarounds/*)
        return 0
        ;;
    esac
  done < <(changed_files)

  return 1
}

discover_hosts() {
  if [[ -n "$HOSTS" ]]
  then
    # Space-separated hostnames: "ge2 gk4 x13"
    read -r -a _hosts <<<"$HOSTS"
    printf '%s\n' "${_hosts[@]}"
    return 0
  fi

  # Use the intersection between base and head to avoid noisy "missing attr" failures.
  local head_json base_json

  head_json="$(nix flake show --json 2>/dev/null)"
  base_json="$(cd "$BASE_WORKTREE" && nix flake show --json 2>/dev/null)"

  comm -12 \
    <(jq -r '.nixosConfigurations | keys[]' <<<"$head_json" | sort -u) \
    <(jq -r '.nixosConfigurations | keys[]' <<<"$base_json" | sort -u)
}

filter_hosts() {
  local host

  while IFS= read -r host
  do
    if [[ "$INCLUDE_ISO" != "1" && "$host" == iso* ]]
    then
      continue
    fi
    printf '%s\n' "$host"
  done
}

select_hosts() {
  local -a all_hosts
  local -a changed
  local file host
  local global_change=
  declare -A wanted=()

  mapfile -t all_hosts < <(discover_hosts | filter_hosts)
  mapfile -t changed < <(changed_files)

  for file in "${changed[@]}"
  do
    case "$file" in
      hosts/*/*)
        host="${file#hosts/}"
        host="${host%%/*}"
        wanted["$host"]=1
        ;;
      flake.nix|flake.lock|common/*|hardware/*|home-manager/*|modules/*|overlays/*|pkgs/*|services/*|workarounds/*|*.nix)
        global_change=1
        ;;
    esac
  done

  if (( ${#wanted[@]} > 0 ))
  then
    for host in "${all_hosts[@]}"
    do
      if [[ -n "${wanted[$host]:-}" ]]
      then
        printf '%s\n' "$host"
      fi
    done
    return 0
  fi

  if [[ -n "${global_change:-}" ]]
  then
    printf '%s\n' "${all_hosts[@]}"
    return 0
  fi

  # No host-scoped changes found; default to all discovered hosts.
  printf '%s\n' "${all_hosts[@]}"
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

write_system_packages() {
  local flake_path="$1"
  local host="$2"
  local out_file="$3"

  nix eval --json \
    "${flake_path}#nixosConfigurations.${host}.config.environment.systemPackages" \
    --apply '
      pkgs:
        let
          norm = p:
            if builtins.isAttrs p then
              {
                name =
                  if p ? pname then p.pname else
                  if p ? name then p.name else
                  builtins.toString p;
                version =
                  if p ? version then p.version else "";
              }
            else
              { name = builtins.toString p; version = ""; };
        in builtins.map norm pkgs
    ' 2>/dev/null | \
    jq -r '.[] | "\(.name) \(.version)"' | \
    sed 's/ $//' | \
    sort -u >"$out_file"
}

diff_for_host() {
  local host="$1"
  local base_pkgs head_pkgs
  local added removed
  local diff_output

  base_pkgs="$(mktemp)"
  head_pkgs="$(mktemp)"

  if ! write_system_packages "$BASE_WORKTREE" "$host" "$base_pkgs"
  then
    printf '%s\n' 'Failed to eval base systemPackages.'
    return 0
  fi

  if ! write_system_packages "." "$host" "$head_pkgs"
  then
    printf '%s\n' 'Failed to eval head systemPackages.'
    return 0
  fi

  added="$(comm -13 "$base_pkgs" "$head_pkgs" | wc -l | tr -d ' ')"
  removed="$(comm -23 "$base_pkgs" "$head_pkgs" | wc -l | tr -d ' ')"

  printf '%s\n' "Added: ${added}, removed: ${removed}"
  printf '\n'

  diff_output="$(diff -u "$base_pkgs" "$head_pkgs" || true)"
  if [[ -z "$diff_output" ]]
  then
    diff_output="(no changes)"
  fi

  diff_output="$(trim_output "$diff_output" "$MAX_LINES")"

  printf '%s\n' '```diff'
  printf '%s\n' "$diff_output"
  printf '%s\n' '```'
}

printf '%s\n' '<!-- pr-systempackages-diff -->'
printf '%s\n' '## NixOS `environment.systemPackages` diff (per host, no builds)'
printf '\n'
printf 'Base: %s\n' "$BASE_SHA"
printf '\n'
printf 'Head: %s\n' "$HEAD_SHA"
printf '\n'

if ! is_nix_related_change
then
  printf '%s\n' 'No Nix-related files changed, skipping.'
  exit 0
fi

mapfile -t hosts < <(select_hosts)
if (( ${#hosts[@]} == 0 ))
then
  printf '%s\n' 'No hosts found.'
  exit 0
fi

for host in "${hosts[@]}"
do
  printf '### %s\n' "$host"
  printf '\n'
  diff_for_host "$host"
  printf '\n'
done

