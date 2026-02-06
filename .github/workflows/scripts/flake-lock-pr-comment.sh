#!/usr/bin/env bash
set -euo pipefail

export NIXPKGS_ALLOW_UNFREE=1
export NIX_CONFIG="accept-flake-config = true${NIX_CONFIG:+ $NIX_CONFIG}"

BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-}"
HOSTS="${HOSTS:-}"
FULL_DIFF="${FULL_DIFF:-0}"
PER_HOST="${PER_HOST:-1}"

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

  # Discover hosts dynamically, instead of hardcoding.
  # Use the intersection between base and head to avoid noisy "missing attr" failures.
  local head_json base_json

  head_json="$(nix flake show --json 2>/dev/null)"
  base_json="$(cd "$BASE_WORKTREE" && nix flake show --json 2>/dev/null)"

  comm -12 \
    <(jq -r '.nixosConfigurations | keys[]' <<<"$head_json" | sort -u) \
    <(jq -r '.nixosConfigurations | keys[]' <<<"$base_json" | sort -u)
}

select_hosts() {
	local -a all_hosts
	local -a changed
	local file host
	local global_change=
	declare -A wanted=()

  mapfile -t all_hosts < <(discover_hosts)
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

  return 0
}

BASE_WORKTREE="$(mktemp -d)"
git worktree add "$BASE_WORKTREE" "$BASE_SHA" >/dev/null

if [[ "$FULL_DIFF" == "1" ]]
then
  nix_diff_store_path="$(nix build --no-link --print-out-paths nixpkgs#nix-diff)"
  nix_diff_bin="$nix_diff_store_path/bin/nix-diff"
fi

eval_toplevel_drvpath() {
  local flake_path="$1"
  local host="$2"

  nix eval --impure --raw \
    "${flake_path}#nixosConfigurations.${host}.config.system.build.toplevel.drvPath"
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

flake_lock_inputs_diff() {
  if ! changed_files | grep -qx 'flake.lock'
  then
    return 0
  fi

  local base_lock head_lock
  base_lock="${BASE_WORKTREE}/flake.lock"
  head_lock="./flake.lock"

  if [[ ! -f "$base_lock" || ! -f "$head_lock" ]]
  then
    printf '%s\n' 'flake.lock missing in base or head, skipping input diff.'
    return 0
  fi

  jq -nr \
    --slurpfile base "$base_lock" \
    --slurpfile head "$head_lock" \
    '
      def lockInfo($x):
        ($x.nodes // {}) as $nodes
        | $nodes
        | to_entries
        | map({
            key: .key,
            type: (.value.locked.type // ""),
            owner: (.value.locked.owner // ""),
            repo: (.value.locked.repo // ""),
            rev: (.value.locked.rev // ""),
            ref: (.value.locked.ref // ""),
            lastModified: (.value.locked.lastModified // null)
          })
        | from_entries;

      (lockInfo($base[0])) as $b
      | (lockInfo($head[0])) as $h
      | (
          ($b | keys_unsorted) + ($h | keys_unsorted)
        ) | unique | sort as $keys
      | [
          $keys[]
          | . as $k
          | ($b[$k] // {}) as $bv
          | ($h[$k] // {}) as $hv
          | select($bv.rev != $hv.rev or $bv.ref != $hv.ref or $bv.lastModified != $hv.lastModified)
          | {
              key: $k,
              from: ($bv.rev // $bv.ref // ""),
              to: ($hv.rev // $hv.ref // ""),
              fromTs: ($bv.lastModified // null),
              toTs: ($hv.lastModified // null)
            }
        ]
      | if length == 0 then
          "No flake inputs changed (unexpected if flake.lock changed)."
        else
          (
            "## Flake inputs changed\n\n"
            + "| Input | From | To |\\n"
            + "|---|---|---|\\n"
            + (
              map("| `\(.key)` | `\(.from)` | `\(.to)` |")
              | join("\\n")
            )
          )
        end
    '
}

printf '%s\n' '<!-- flake-lock-diff -->'
printf '%s\n' '## Flake lock update'
printf '\n'
printf 'Base: %s\n' "$BASE_SHA"
printf '\n'
printf 'Head: %s\n' "$HEAD_SHA"
printf '\n'

flake_lock_inputs_diff
printf '\n'

if ! is_nix_related_change
then
  printf '%s\n' 'No Nix-related files changed, skipping.'
  exit 0
fi

if [[ "$PER_HOST" != "1" ]]
then
  printf '%s\n' '## Per-host diffs'
  printf '\n'
  printf '%s\n' 'Per-host diffs are disabled by default (they are expensive even without builds).'
  printf '%s\n' 'Set PER_HOST=1 to enable, and optionally set HOSTS="ge2 gk4" to limit.'
  exit 0
fi

mapfile -t hosts < <(select_hosts)
if (( ${#hosts[@]} == 0 ))
then
  printf '%s\n' 'No hosts selected for per-host diff.'
  exit 0
fi

printf '%s\n' '## Per-host summary (no builds)'
printf '\n'

for host in "${hosts[@]}"
do
  printf '### %s\n' "$host"
  printf '\n'

  if ! base_drv="$(eval_toplevel_drvpath "$BASE_WORKTREE" "$host" 2>/dev/null)"
  then
    printf '%s\n' 'Eval failed for base revision.'
    printf '\n'
    continue
  fi

  if ! head_drv="$(eval_toplevel_drvpath "." "$host" 2>/dev/null)"
  then
    printf '%s\n' 'Eval failed for head revision.'
    printf '\n'
    continue
  fi

  if [[ "$base_drv" == "$head_drv" ]]
  then
    diff_output="(toplevel derivation unchanged)"
  else
    diff_output="$(printf 'Base: %s\nHead: %s\n\n' "$base_drv" "$head_drv")"
    if [[ "$FULL_DIFF" == "1" ]]
    then
      diff_output="$("$nix_diff_bin" "$base_drv" "$head_drv" --color never --skip-already-compared 2>/dev/null || true)"
    else
      diff_output="${diff_output}Set FULL_DIFF=1 to include nix-diff output."
    fi
  fi

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
