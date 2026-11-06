#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
initializer="${script_dir}/rclone-config-init.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  [[ "$actual" == "$expected" ]] || fail "$description"
}

assert_mode() {
  local expected="$1"
  local path="$2"
  local actual

  actual="$(stat -c '%a' "$path")"
  assert_equal "$expected" "$actual" "unexpected permissions on $path"
}

runtime_dir="${test_root}/runtime"
mkdir -m 0700 "$runtime_dir"
seed="${test_root}/seed.conf"
runtime="${runtime_dir}/rclone.conf"
printf '[remote]\ntype = dummy\n' > "$seed"
chmod 0600 "$seed"

# First invocation seeds a private config file.
bash -euo pipefail "$initializer" "$runtime" "$seed"
cmp -s "$seed" "$runtime" || fail 'initial seed did not match runtime file'
assert_mode 600 "$runtime"

# A runtime edit survives later runs and a changed encrypted seed.
printf '\nrefreshed = yes\n' >> "$runtime"
printf '[remote]\ntype = dummy\nseed = newer\n' > "$seed"
bash -euo pipefail "$initializer" "$runtime" "$seed"
grep -q '^refreshed = yes$' "$runtime" || fail 'runtime edit was overwritten'
grep -q '^seed = newer$' "$runtime" && fail 'changed seed overwrote runtime config'
assert_mode 600 "$runtime"

# Concurrent first invocations both succeed and leave one complete file.
concurrent_dir="${test_root}/concurrent"
mkdir -m 0700 "$concurrent_dir"
concurrent_runtime="${concurrent_dir}/rclone.conf"
bash -euo pipefail "$initializer" "$concurrent_runtime" "$seed" &
first_pid=$!
bash -euo pipefail "$initializer" "$concurrent_runtime" "$seed" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
cmp -s "$seed" "$concurrent_runtime" || fail 'concurrent seed produced incomplete file'
assert_mode 600 "$concurrent_runtime"

# A missing first seed fails without creating runtime config or temp files.
missing_dir="${test_root}/missing-seed"
mkdir -m 0700 "$missing_dir"
if bash -euo pipefail "$initializer" "${missing_dir}/rclone.conf" "${test_root}/absent.conf" 2>/dev/null
then
  fail 'missing seed unexpectedly succeeded'
fi
[[ ! -e "${missing_dir}/rclone.conf" ]] || fail 'missing seed created runtime config'
shopt -s nullglob
temporary_files=("${missing_dir}"/.rclone-config.*)
[[ "${#temporary_files[@]}" -eq 0 ]] || fail 'missing seed left a temporary file behind'

empty_seed="${test_root}/empty-seed.conf"
: > "$empty_seed"
if bash -euo pipefail "$initializer" "${missing_dir}/empty-seed.conf" "$empty_seed" 2>/dev/null
then
  fail 'empty seed unexpectedly succeeded'
fi
[[ ! -e "${missing_dir}/empty-seed.conf" ]] || fail 'empty seed created runtime config'

# Existing valid runtime state remains usable even if the seed is unavailable.
preserved_runtime="${test_root}/preserved.conf"
printf '[remote]\ntype = dummy\nrefreshed = yes\n' > "$preserved_runtime"
chmod 0600 "$preserved_runtime"
cp "$preserved_runtime" "${test_root}/preserved.expected"
bash -euo pipefail "$initializer" "$preserved_runtime" "${test_root}/absent.conf"
cmp -s "${test_root}/preserved.expected" "$preserved_runtime" || fail 'existing config changed with missing seed'
assert_mode 600 "$preserved_runtime"

# Empty and non-regular existing files fail closed.
empty_runtime="${test_root}/empty.conf"
: > "$empty_runtime"
if bash -euo pipefail "$initializer" "$empty_runtime" "$seed" 2>/dev/null
then
  fail 'empty runtime config unexpectedly succeeded'
fi
symlink_runtime="${test_root}/symlink.conf"
ln -s "$seed" "$symlink_runtime"
if bash -euo pipefail "$initializer" "$symlink_runtime" "$seed" 2>/dev/null
then
  fail 'symlink runtime config unexpectedly succeeded'
fi

printf 'PASS: rclone config initialization\n'

# vim: set ft=sh et ts=2 sw=2 :
