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

  if [[ -n "${RUN_DIR:-}" && -d "${RUN_DIR:-}" ]]
  then
    rm -rf "$RUN_DIR"
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

  # shellcheck disable=SC2016
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

write_kernel_info() {
  local flake_path="$1"
  local host="$2"
  local out_json_file="$3"
  local out_human_file="$4"
  local err_file="$5"
  local json_file

  json_file="$(mktemp)"

  # shellcheck disable=SC2016
  if ! nix eval --json \
    "${flake_path}#nixosConfigurations.${host}.config.boot.kernelPackages.kernel" \
    --apply '
      k:
        {
          pname =
            if builtins.isAttrs k && k ? pname then
              k.pname
            else if builtins.isAttrs k && k ? name then
              k.name
            else
              builtins.toString k;
          version =
            if builtins.isAttrs k && k ? version then
              k.version
            else
              "";
          modDirVersion =
            if builtins.isAttrs k && k ? modDirVersion then
              k.modDirVersion
            else
              "";
        }
    ' >"$json_file" 2>"$err_file"
  then
    rm -f "$json_file"
    return 1
  fi

  if ! jq -cS '.' <"$json_file" >"$out_json_file" 2>>"$err_file"
  then
    rm -f "$json_file"
    return 1
  fi

  if ! jq -r '
      . as $o
      | [
          ($o.pname // "" | tostring),
          ($o.version // "" | tostring)
        ]
      | map(select(length > 0))
      | join(" ") as $base
      | if ($o.modDirVersion // "") != "" and ($o.modDirVersion // "") != ($o.version // "") then
          ($base + " (modDirVersion " + ($o.modDirVersion | tostring) + ")")
        else
          $base
        end
    ' <"$json_file" >"$out_human_file" 2>>"$err_file"
  then
    rm -f "$json_file"
    return 1
  fi

  rm -f "$json_file"
}

write_home_manager_packages() {
  local flake_path="$1"
  local host="$2"
  local out_file="$3"
  local err_file="$4"

  local json_file
  json_file="$(mktemp)"

  # shellcheck disable=SC2016
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

write_host_packages_norm() {
  local flake_path="$1"
  local host="$2"
  local out_file="$3"
  local err_file="$4"

  local sys_file
  sys_file="$(mktemp)"

  if ! write_system_packages "$flake_path" "$host" "$sys_file" "$err_file"
  then
    rm -f "$sys_file"
    return 1
  fi

  local hm_file
  hm_file="$(mktemp)"

  local hm_err
  hm_err="$(mktemp)"

  set +e
  write_home_manager_packages "$flake_path" "$host" "$hm_file" "$hm_err"
  local hm_status="$?"
  set -e

  if [[ "$hm_status" != "0" && "$hm_status" != "2" ]]
  then
    cat "$hm_err" >>"$err_file" || true
    rm -f "$sys_file" "$hm_file" "$hm_err"
    return 2
  fi

  if [[ "$hm_status" == "2" ]]
  then
    : >"$hm_file"
  fi

  {
    cat "$sys_file"
    sed 's/^[^:]*: //' "$hm_file"
  } | sort -u >"$out_file"

  rm -f "$sys_file" "$hm_file" "$hm_err"
}

compute_changes() {
  local base_file="$1"
  local head_file="$2"
  local out_added="$3"
  local out_removed="$4"
  local out_upgrades="$5"

  local added_tmp
  added_tmp="$(mktemp)"

  local removed_tmp
  removed_tmp="$(mktemp)"

  comm -13 "$base_file" "$head_file" >"$added_tmp" || true
  comm -23 "$base_file" "$head_file" >"$removed_tmp" || true

  awk '
    function rest_of_line(start,    s, i) {
      s=""
      for (i=start; i<=NF; i++) {
        s = s (i==start ? "" : " ") $i
      }
      return s
    }
    FNR==NR {
      name=$1
      ver=rest_of_line(2)
      rem[name]=ver
      remc[name]++
      next
    }
    {
      name=$1
      ver=rest_of_line(2)
      add[name]=ver
      addc[name]++
    }
    END {
      for (n in remc) {
        if (remc[n]==1 && addc[n]==1) {
          print n "\t" rem[n] "\t" add[n]
        }
      }
    }
  ' "$removed_tmp" "$added_tmp" | sort -u >"$out_upgrades"

  local upgraded_removed
  upgraded_removed="$(mktemp)"

  local upgraded_added
  upgraded_added="$(mktemp)"

  awk -F'\t' '{ if ($2 == "") { print $1 } else { print $1 " " $2 } }' "$out_upgrades" | sort -u >"$upgraded_removed"
  awk -F'\t' '{ if ($3 == "") { print $1 } else { print $1 " " $3 } }' "$out_upgrades" | sort -u >"$upgraded_added"

  comm -23 "$removed_tmp" "$upgraded_removed" >"$out_removed" || true
  comm -23 "$added_tmp" "$upgraded_added" >"$out_added" || true

  rm -f "$added_tmp" "$removed_tmp" "$upgraded_removed" "$upgraded_added"
}

changes_signature() {
  local added="$1"
  local removed="$2"
  local upgrades="$3"

  {
    printf '%s\n' 'ADDED'
    cat "$added"
    printf '%s\n' 'REMOVED'
    cat "$removed"
    printf '%s\n' 'UPGRADES'
    cat "$upgrades"
  } | sha256sum | awk '{print $1}'
}

join_hosts_csv() {
  local hosts_file="$1"

  awk '
    NR==1 { out=$0; next }
    { out = out ", " $0 }
    END { print out }
  ' < <(sort -u "$hosts_file")
}

print_changes_diff() {
  local added_file="$1"
  local removed_file="$2"
  local upgrades_file="$3"

  if [[ ! -s "$added_file" && ! -s "$removed_file" && ! -s "$upgrades_file" ]]
  then
    printf '%s\n' '(no package changes)'
    return 0
  fi

  printf '%s\n' '```diff'

  if [[ -s "$upgrades_file" ]]
  then
    while IFS=$'\t' read -r name old_ver new_ver
    do
      if [[ -n "${old_ver:-}" ]]
      then
        printf -- '- %s %s\n' "$name" "$old_ver"
      else
        printf -- '- %s\n' "$name"
      fi

      if [[ -n "${new_ver:-}" ]]
      then
        printf -- '+ %s %s\n' "$name" "$new_ver"
      else
        printf -- '+ %s\n' "$name"
      fi
    done <"$upgrades_file"
  fi

  if [[ -s "$removed_file" ]]
  then
    while IFS= read -r line
    do
      printf -- '- %s\n' "$line"
    done <"$removed_file"
  fi

  if [[ -s "$added_file" ]]
  then
    while IFS= read -r line
    do
      printf -- '+ %s\n' "$line"
    done <"$added_file"
  fi

  printf '%s\n' '```'
}

print_common_summary() {
  local ok_hosts_file="$1"
  local excluded_count="$2"
  local common_added="$3"
  local common_removed="$4"
  local common_upgrades="$5"

  local ok_count
  ok_count="$(wc -l <"$ok_hosts_file" | tr -d ' ')"

  printf '### Common changes (across %s host(s))\n' "$ok_count"
  printf '\n'

  printf 'Hosts: %s\n' "$(join_hosts_csv "$ok_hosts_file")"
  printf '\n'

  if (( excluded_count > 0 ))
  then
    printf 'Note: excluded %s host(s) from the summary due to eval failures.\n' "$excluded_count"
    printf '\n'
  fi

  print_changes_diff "$common_added" "$common_removed" "$common_upgrades"
  printf '\n'
}

print_kernel_updates() {
  local groups_dir="$1"
  local ok_hosts_file="$2"
  local excluded_count="$3"

  if ! ls "$groups_dir"/*.hosts >/dev/null 2>&1
  then
    return 0
  fi

  local ok_count
  ok_count="$(wc -l <"$ok_hosts_file" | tr -d ' ')"

  printf '%s\n' '## Kernel updates (boot.kernelPackages.kernel)'
  printf '\n'
  printf 'Hosts evaluated: %s\n' "$ok_count"
  printf '\n'

  if (( excluded_count > 0 ))
  then
    printf 'Note: failed to evaluate kernel for %s host(s).\n' "$excluded_count"
    printf '\n'
  fi

  local tmp_list
  tmp_list="$(mktemp)"

  local hosts_file
  for hosts_file in "$groups_dir"/*.hosts
  do
    if [[ ! -f "$hosts_file" ]]
    then
      continue
    fi
    local count
    count="$(wc -l <"$hosts_file" | tr -d ' ')"
    printf '%s\t%s\n' "$count" "$hosts_file" >>"$tmp_list"
  done

  while IFS=$'\t' read -r _count file
  do
    local sig
    sig="$(basename "$file" .hosts)"

    local rep_dir
    rep_dir="$(cat "$groups_dir/${sig}.repdir")"

    local hosts_csv
    hosts_csv="$(join_hosts_csv "$file")"

    printf '### Hosts: %s\n' "$hosts_csv"
    printf '\n'
    printf '%s\n' '```diff'
    printf -- '- %s\n' "$(cat "${rep_dir}/kernel.base")"
    printf -- '+ %s\n' "$(cat "${rep_dir}/kernel.head")"
    printf '%s\n' '```'
    printf '\n'
  done < <(sort -rn "$tmp_list")

  rm -f "$tmp_list"
}

print_group_extras() {
  local groups_dir="$1"
  local common_added="$2"
  local common_removed="$3"
  local common_upgrades="$4"

  local tmp_list
  tmp_list="$(mktemp)"

  local hosts_file
  for hosts_file in "$groups_dir"/*.hosts
  do
    if [[ ! -f "$hosts_file" ]]
    then
      continue
    fi
    local count
    count="$(wc -l <"$hosts_file" | tr -d ' ')"
    printf '%s\t%s\n' "$count" "$hosts_file" >>"$tmp_list"
  done

  local shown_any=
  while IFS=$'\t' read -r _count file
  do
    local sig
    sig="$(basename "$file" .hosts)"

    local rep_dir
    rep_dir="$(cat "$groups_dir/${sig}.repdir")"

    local hosts_csv
    hosts_csv="$(join_hosts_csv "$file")"

    local extra_added
    extra_added="$(mktemp)"

    local extra_removed
    extra_removed="$(mktemp)"

    local extra_upgrades
    extra_upgrades="$(mktemp)"

    comm -23 "${rep_dir}/added" "$common_added" >"$extra_added" || true
    comm -23 "${rep_dir}/removed" "$common_removed" >"$extra_removed" || true
    comm -23 "${rep_dir}/upgrades" "$common_upgrades" >"$extra_upgrades" || true

    if [[ -s "$extra_added" || -s "$extra_removed" || -s "$extra_upgrades" ]]
    then
      if [[ -z "${shown_any:-}" ]]
      then
        printf '%s\n' '### Additional changes (per host group)'
        printf '\n'
      fi

      printf '#### Hosts: %s\n' "$hosts_csv"
      printf '\n'
      print_changes_diff "$extra_added" "$extra_removed" "$extra_upgrades"
      printf '\n'
      shown_any=1
    fi

    rm -f "$extra_added" "$extra_removed" "$extra_upgrades"
  done < <(sort -rn "$tmp_list")

  rm -f "$tmp_list"
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

  RUN_DIR="$(mktemp -d)"
  BASE_WORKTREE="$(mktemp -d)"
  git worktree add "$BASE_WORKTREE" "$BASE_SHA" >/dev/null

  printf '%s\n' '<!-- pr-systempackages-diff -->'
  printf '%s\n' '## NixOS packages diff (system + home-manager, no builds)'
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

  local excluded_count=0

  local groups_dir
  groups_dir="${RUN_DIR}/groups"
  mkdir -p "$groups_dir"

  local kernel_groups_dir
  kernel_groups_dir="${RUN_DIR}/kernel.groups"
  mkdir -p "$kernel_groups_dir"

  local kernel_ok_hosts_file
  kernel_ok_hosts_file="${RUN_DIR}/kernel.ok.hosts"
  : >"$kernel_ok_hosts_file"

  local kernel_excluded_count=0

  local ok_hosts_file
  ok_hosts_file="${RUN_DIR}/ok.hosts"
  : >"$ok_hosts_file"

  local common_added
  common_added="${RUN_DIR}/common.added"

  local common_removed
  common_removed="${RUN_DIR}/common.removed"

  local common_upgrades
  common_upgrades="${RUN_DIR}/common.upgrades"

  local first_ok=1

  local host
  for host in "${hosts[@]}"
  do
    local host_dir
    host_dir="${RUN_DIR}/hosts/${host}"
    mkdir -p "$host_dir"

    local kernel_base_ok=
    local kernel_head_ok=

    if write_kernel_info "$BASE_WORKTREE" "$host" "${host_dir}/kernel.base.json" "${host_dir}/kernel.base" "${host_dir}/kernel.base.err"
    then
      kernel_base_ok=1
    fi

    if write_kernel_info "." "$host" "${host_dir}/kernel.head.json" "${host_dir}/kernel.head" "${host_dir}/kernel.head.err"
    then
      kernel_head_ok=1
    fi

    if [[ -n "${kernel_base_ok:-}" && -n "${kernel_head_ok:-}" ]]
    then
      printf '%s\n' "$host" >>"$kernel_ok_hosts_file"

      if ! cmp -s "${host_dir}/kernel.base.json" "${host_dir}/kernel.head.json"
      then
        local kernel_sig
        kernel_sig="$(sha256sum "${host_dir}/kernel.base.json" "${host_dir}/kernel.head.json" | sha256sum | awk '{print $1}')"
        printf '%s\n' "$host" >>"${kernel_groups_dir}/${kernel_sig}.hosts"
        if [[ ! -f "${kernel_groups_dir}/${kernel_sig}.repdir" ]]
        then
          printf '%s\n' "$host_dir" >"${kernel_groups_dir}/${kernel_sig}.repdir"
        fi
      fi
    else
      kernel_excluded_count=$((kernel_excluded_count + 1))
    fi

    if ! write_host_packages_norm "$BASE_WORKTREE" "$host" "${host_dir}/base.pkgs" "${host_dir}/base.err"
    then
      excluded_count=$((excluded_count + 1))
      printf '%s\n' 'fail' >"${host_dir}/status"
      continue
    fi

    if ! write_host_packages_norm "." "$host" "${host_dir}/head.pkgs" "${host_dir}/head.err"
    then
      excluded_count=$((excluded_count + 1))
      printf '%s\n' 'fail' >"${host_dir}/status"
      continue
    fi

    compute_changes "${host_dir}/base.pkgs" "${host_dir}/head.pkgs" "${host_dir}/added" "${host_dir}/removed" "${host_dir}/upgrades"
    printf '%s\n' 'ok' >"${host_dir}/status"
    printf '%s\n' "$host" >>"$ok_hosts_file"

    if [[ -n "${first_ok:-}" ]]
    then
      cat "${host_dir}/added" >"$common_added"
      cat "${host_dir}/removed" >"$common_removed"
      cat "${host_dir}/upgrades" >"$common_upgrades"
      first_ok=
    else
      comm -12 "$common_added" "${host_dir}/added" >"${common_added}.tmp" || true
      mv "${common_added}.tmp" "$common_added"

      comm -12 "$common_removed" "${host_dir}/removed" >"${common_removed}.tmp" || true
      mv "${common_removed}.tmp" "$common_removed"

      comm -12 "$common_upgrades" "${host_dir}/upgrades" >"${common_upgrades}.tmp" || true
      mv "${common_upgrades}.tmp" "$common_upgrades"
    fi

    local sig
    sig="$(changes_signature "${host_dir}/added" "${host_dir}/removed" "${host_dir}/upgrades")"
    printf '%s\n' "$host" >>"${groups_dir}/${sig}.hosts"
    if [[ ! -f "${groups_dir}/${sig}.repdir" ]]
    then
      printf '%s\n' "$host_dir" >"${groups_dir}/${sig}.repdir"
    fi
  done

  if ! ls "$groups_dir"/*.hosts >/dev/null 2>&1
  then
    printf '%s\n' 'Failed to evaluate packages for all selected hosts.'
    exit 0
  fi

  print_kernel_updates "$kernel_groups_dir" "$kernel_ok_hosts_file" "$kernel_excluded_count"
  print_common_summary "$ok_hosts_file" "$excluded_count" "$common_added" "$common_removed" "$common_upgrades"
  print_group_extras "$groups_dir" "$common_added" "$common_removed" "$common_upgrades"

  printf '%s\n' '<details>'
  printf '  <summary>Per-host details (%s host(s))</summary>\n' "${#hosts[@]}"
  printf '\n'

  for host in "${hosts[@]}"
  do
    printf '### %s\n' "$host"
    printf '\n'
    local host_dir
    host_dir="${RUN_DIR}/hosts/${host}"

    if [[ -s "${host_dir}/kernel.base" && -s "${host_dir}/kernel.head" ]]
    then
      if cmp -s "${host_dir}/kernel.base" "${host_dir}/kernel.head"
      then
        printf 'Kernel: %s (unchanged)\n' "$(cat "${host_dir}/kernel.head")"
      else
        printf 'Kernel: %s -> %s\n' "$(cat "${host_dir}/kernel.base")" "$(cat "${host_dir}/kernel.head")"
      fi
      printf '\n'
    else
      if [[ -s "${host_dir}/kernel.base.err" ]]
      then
        print_eval_error 'Failed to eval base kernel' "${host_dir}/kernel.base.err" 30
        printf '\n'
      fi
      if [[ -s "${host_dir}/kernel.head.err" ]]
      then
        print_eval_error 'Failed to eval head kernel' "${host_dir}/kernel.head.err" 30
        printf '\n'
      fi
    fi

    if [[ ! -d "$host_dir" || ! -f "${host_dir}/status" ]]
    then
      printf '%s\n' '(no data)'
      printf '\n'
      continue
    fi

    if [[ "$(cat "${host_dir}/status")" != "ok" ]]
    then
      if [[ -s "${host_dir}/base.err" ]]
      then
        print_eval_error 'Failed to eval base packages (system + home-manager)' "${host_dir}/base.err" 60
      fi
      if [[ -s "${host_dir}/head.err" ]]
      then
        print_eval_error 'Failed to eval head packages (system + home-manager)' "${host_dir}/head.err" 60
      fi
      printf '\n'
      continue
    fi

    local added_count
    added_count="$(wc -l <"${host_dir}/added" | tr -d ' ')"

    local removed_count
    removed_count="$(wc -l <"${host_dir}/removed" | tr -d ' ')"

    local upgrades_count
    upgrades_count="$(wc -l <"${host_dir}/upgrades" | tr -d ' ')"

    printf '%s\n' "Upgrades: ${upgrades_count}, added: ${added_count}, removed: ${removed_count}"
    printf '\n'

    print_changes_diff "${host_dir}/added" "${host_dir}/removed" "${host_dir}/upgrades"
    printf '\n'
  done

  printf '%s\n' '</details>'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set shiftwidth=2 softtabstop=2 expandtab :
