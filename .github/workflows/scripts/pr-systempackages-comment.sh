#!/usr/bin/env bash

set -euo pipefail

export NIXPKGS_ALLOW_UNFREE=1
export NIX_CONFIG="accept-flake-config = true${NIX_CONFIG:+ $NIX_CONFIG}"

BASE_SHA=
HEAD_SHA=
TARGET_HOSTS_INPUT=
MAX_LINES=
INCLUDE_ISO=

usage() {
  local prog

  prog="$(basename "$0")"

  cat <<EOF
Usage:
  ${prog} [--host HOST]...

Options:
  --host HOST     Limit diff to a single host. Can be repeated.
  -h, --help      Show this help.

Environment:
  BASE_SHA        Base commit SHA (defaults to HEAD^)
  HEAD_SHA        Head commit SHA (defaults to HEAD)
  TARGET_HOSTS    Space-separated hostnames (alternative to --host)
  MAX_LINES       Max lines per diff block (default: 400)
  INCLUDE_ISO     Include iso* hosts (default: 1)
EOF
}

declare -a TARGET_HOSTS_ARR=()

append_host() {
  local host="$1"

  if [[ -z "$host" ]]
  then
    return 0
  fi

  TARGET_HOSTS_ARR+=("$host")
}

load_target_hosts_env() {
  if [[ -z "${TARGET_HOSTS_INPUT:-}" ]]
  then
    return 0
  fi

  local -a _hosts
  read -r -a _hosts <<<"$TARGET_HOSTS_INPUT"

  local h
  for h in "${_hosts[@]}"
  do
    append_host "$h"
  done
}

parse_args() {
  while (( $# > 0 ))
  do
    case "$1" in
      --host)
        shift
        if (( $# == 0 ))
        then
          echo "--host requires a value" >&2
          exit 2
        fi
        append_host "$1"
        ;;
      --host=*)
        append_host "${1#--host=}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  if (( ${#TARGET_HOSTS_ARR[@]} == 0 ))
  then
    load_target_hosts_env
  fi
}

git_is_dirty() {
  if ! git diff --quiet
  then
    return 0
  fi

  if ! git diff --cached --quiet
  then
    return 0
  fi

  return 1
}

default_shas() {
  if [[ -z "$HEAD_SHA" ]]
  then
    HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
  fi

  if [[ -z "$BASE_SHA" ]]
  then
    if git rev-parse --verify HEAD^ >/dev/null 2>&1
    then
      BASE_SHA="$(git rev-parse HEAD^)"
    else
      BASE_SHA=""
    fi
  fi
}

cleanup() {
  if [[ -n "${BASE_WORKTREE:-}" ]]
  then
    git worktree remove "$BASE_WORKTREE" --force
  fi
}

changed_files() {
  # Include:
  # - committed diff between BASE_SHA and HEAD_SHA
  # - staged changes vs BASE_SHA
  # - unstaged changes vs BASE_SHA
  {
    git diff --name-only "$BASE_SHA" "$HEAD_SHA" || true
    git diff --name-only --cached "$BASE_SHA" || true
    git diff --name-only "$BASE_SHA" || true
  } | sort -u
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
  if (( ${#TARGET_HOSTS_ARR[@]} > 0 ))
  then
    printf '%s\n' "${TARGET_HOSTS_ARR[@]}" | sort -u
    return 0
  fi

  # Use the intersection between base and head to avoid noisy "missing attr" failures.
  local head_json
  head_json="$(nix flake show --json 2>/dev/null)"

  local base_json
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
  mapfile -t all_hosts < <(discover_hosts | filter_hosts)

  local -a changed
  mapfile -t changed < <(changed_files)

  declare -A wanted=()
  local global_change=

  local file
  for file in "${changed[@]}"
  do
    case "$file" in
      hosts/*/*)
        local host
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
    local host
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

print_eval_error() {
  local label="$1"
  local err_file="$2"
  local max_lines="$3"

  if [[ ! -s "$err_file" ]]
  then
    printf '%s\n' "${label}: (no error output)"
    return 0
  fi

  local err
  err="$(cat "$err_file")"
  err="$(trim_output "$err" "$max_lines")"

  printf '%s\n' "$label:"
  printf '\n'
  printf '%s\n' '```'
  printf '%s\n' "$err"
  printf '%s\n' '```'
}

write_system_packages() {
  local flake_path="$1"
  local host="$2"
  local out_file="$3"
  local err_file="$4"
  local json_file

  json_file="$(mktemp)"

  if ! nix eval --json \
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
    ' >"$json_file" 2>"$err_file"
  then
    rm -f "$json_file"
    return 1
  fi

  jq -r '.[] | "\(.name) \(.version)"' <"$json_file" | \
    sed 's/ $//' | \
    sort -u >"$out_file"

  rm -f "$json_file"
}

write_home_manager_packages() {
  local flake_path="$1"
  local host="$2"
  local out_file="$3"
  local err_file="$4"

  local json_file
  json_file="$(mktemp)"

  if ! nix eval --json \
    "${flake_path}#nixosConfigurations.${host}.config" \
    --apply '
      cfg:
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

          hm =
            if cfg ? "home-manager" then
              cfg."home-manager"
            else
              null;

          users =
            if hm != null && builtins.isAttrs hm && hm ? users then
              hm.users
            else
              {};

          user_names = builtins.attrNames users;

          packages_for = u:
            let
              ucfg = users.${u};
            in
              if builtins.isAttrs ucfg
              && ucfg ? home
              && builtins.isAttrs ucfg.home
              && ucfg.home ? packages then
                ucfg.home.packages
              else
                [];

          annotate = u: p: (norm p) // { user = u; };
          pkgs =
            builtins.concatLists (
              map (u: map (p: annotate u p) (packages_for u)) user_names
            );
        in
          {
            enabled = hm != null && builtins.isAttrs hm && hm ? users;
            users = user_names;
            pkgs = pkgs;
          }
    ' >"$json_file" 2>"$err_file"
  then
    rm -f "$json_file"
    return 1
  fi

  local hm_json
  hm_json="$(cat "$json_file")"
  rm -f "$json_file"

  if ! jq -e '.enabled' <<<"$hm_json" >/dev/null
  then
    : >"$out_file"
    return 2
  fi

  jq -r '.pkgs[] | "\(.user): \(.name) \(.version)"' <<<"$hm_json" | \
    sed 's/ $//' | \
    sort -u >"$out_file"
}

diff_for_host() {
  local host="$1"

  printf '%s\n' '#### systemPackages'
  printf '\n'

  local base_pkgs
  base_pkgs="$(mktemp)"

  local head_pkgs
  head_pkgs="$(mktemp)"

  local base_err
  base_err="$(mktemp)"

  local head_err
  head_err="$(mktemp)"

  if ! write_system_packages "$BASE_WORKTREE" "$host" "$base_pkgs" "$base_err"
  then
    print_eval_error 'Failed to eval base systemPackages' "$base_err" 60
    return 0
  fi

  if ! write_system_packages "." "$host" "$head_pkgs" "$head_err"
  then
    print_eval_error 'Failed to eval head systemPackages' "$head_err" 60
    return 0
  fi

  local added
  added="$(comm -13 "$base_pkgs" "$head_pkgs" | wc -l | tr -d ' ')"

  local removed
  removed="$(comm -23 "$base_pkgs" "$head_pkgs" | wc -l | tr -d ' ')"

  printf '%s\n' "Added: ${added}, removed: ${removed}"
  printf '\n'

  local diff_output
  diff_output="$(diff -u "$base_pkgs" "$head_pkgs" || true)"
  if [[ -z "$diff_output" ]]
  then
    diff_output="(no changes)"
  fi

  diff_output="$(trim_output "$diff_output" "$MAX_LINES")"

  printf '%s\n' '```diff'
  printf '%s\n' "$diff_output"
  printf '%s\n' '```'

  printf '\n'
  printf '%s\n' '#### home-manager `home.packages`'
  printf '\n'

  local base_hm
  base_hm="$(mktemp)"

  local head_hm
  head_hm="$(mktemp)"

  local hm_base_err
  hm_base_err="$(mktemp)"

  local hm_head_err
  hm_head_err="$(mktemp)"

  set +e
  write_home_manager_packages "$BASE_WORKTREE" "$host" "$base_hm" "$hm_base_err"
  local hm_base_status="$?"
  set -e
  if [[ "$hm_base_status" != "0" && "$hm_base_status" != "2" ]]
  then
    print_eval_error 'Failed to eval base home-manager packages' "$hm_base_err" 60
    return 0
  fi

  set +e
  write_home_manager_packages "." "$host" "$head_hm" "$hm_head_err"
  local hm_head_status="$?"
  set -e
  if [[ "$hm_head_status" != "0" && "$hm_head_status" != "2" ]]
  then
    print_eval_error 'Failed to eval head home-manager packages' "$hm_head_err" 60
    return 0
  fi

  if [[ "$hm_base_status" == "2" && "$hm_head_status" == "2" ]]
  then
    printf '%s\n' '(home-manager not enabled on this host)'
    return 0
  fi

  added="$(comm -13 "$base_hm" "$head_hm" | wc -l | tr -d ' ')"
  removed="$(comm -23 "$base_hm" "$head_hm" | wc -l | tr -d ' ')"

  printf '%s\n' "Added: ${added}, removed: ${removed}"
  printf '\n'

  diff_output="$(diff -u "$base_hm" "$head_hm" || true)"
  if [[ -z "$diff_output" ]]
  then
    diff_output="(no changes)"
  fi

  diff_output="$(trim_output "$diff_output" "$MAX_LINES")"

  printf '%s\n' '```diff'
  printf '%s\n' "$diff_output"
  printf '%s\n' '```'
}

main() {
  BASE_SHA="${BASE_SHA:-}"
  HEAD_SHA="${HEAD_SHA:-}"
  TARGET_HOSTS_INPUT="${TARGET_HOSTS:-}"
  MAX_LINES="${MAX_LINES:-400}"
  INCLUDE_ISO="${INCLUDE_ISO:-1}"

  parse_args "$@"

  default_shas
  if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" ]]
  then
    echo "BASE_SHA and HEAD_SHA must be set (or inferable from git history)" >&2
    exit 1
  fi

  trap cleanup EXIT

  BASE_WORKTREE="$(mktemp -d)"
  git worktree add "$BASE_WORKTREE" "$BASE_SHA" >/dev/null

  printf '%s\n' '<!-- pr-systempackages-diff -->'
  printf '%s\n' '## NixOS packages diff (per host, no builds)'
  printf '\n'
  printf 'Base: %s\n' "$BASE_SHA"
  printf '\n'
  printf 'Head: %s\n' "$HEAD_SHA"
  printf '\n'
  if git_is_dirty
  then
    printf '%s\n' 'Note: working tree has uncommitted changes; "Head" eval includes them.'
    printf '\n'
  fi

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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
