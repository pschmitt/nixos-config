#!/usr/bin/env bash

assert_not_grep() {
  local pattern=$1 file=$2
  if grep -Fq -- "$pattern" "$file"
  then
    printf 'Unexpected match in %s: %s\n' "$file" "$pattern" >&2
    return 1
  fi
}

main() (
  set -euo pipefail
  local script_dir temporary root generation retained_generation
  script_dir=$(dirname "${BASH_SOURCE[0]}")
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/termux-native-apt-test.XXXXXXXX")
  trap 'rm -rf -- "$temporary"' EXIT
  root="$temporary/home/.local/share/termux-native"
  generation=$(printf '%064d' 1)
  retained_generation=$(printf '%064d' 2)
  mkdir -p "$temporary/mock-bin" "$root/generations/$generation" \
    "$root/generations/$retained_generation"
  export MOCK_INSTALLED_FILE="$temporary/installed-packages.txt"
  export MOCK_APT_LOG="$temporary/apt.log"
  : > "$MOCK_APT_LOG"
  printf '%s\n' preexisting-package > "$MOCK_INSTALLED_FILE"
  cat > "$temporary/mock-bin/dpkg-query" <<'MOCK_DPKG_QUERY'
#!/usr/bin/env bash
package=${!#}
if grep -Fxq -- "$package" "$MOCK_INSTALLED_FILE"
then
  printf 'install ok installed\n'
else
  exit 1
fi
MOCK_DPKG_QUERY
  cat > "$temporary/mock-bin/pkg" <<'MOCK_PKG'
#!/usr/bin/env bash
[[ "$1" == install && "$2" == -y ]] || exit 2
shift 2
printf '%s\n' "$@" >> "$MOCK_INSTALLED_FILE"
MOCK_PKG
  cat > "$temporary/mock-bin/apt-get" <<'MOCK_APT_GET'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_APT_LOG"
[[ "$*" != *autoremove* ]] || exit 3
package=${!#}
if [[ "$1" == -s ]]
then
  printf 'Remv %s [1.0]\n' "$package"
  if [[ "$package" == protected-obsolete ]]
  then
    printf 'Remv package-used-elsewhere [1.0]\n'
  fi
  exit 0
fi
temporary=$(mktemp "$MOCK_INSTALLED_FILE.XXXXXXXX")
grep -Fxv -- "$package" "$MOCK_INSTALLED_FILE" > "$temporary" || true
mv -f -- "$temporary" "$MOCK_INSTALLED_FILE"
MOCK_APT_GET
  chmod +x "$temporary/mock-bin/dpkg-query" "$temporary/mock-bin/pkg" "$temporary/mock-bin/apt-get"
  export PATH="$temporary/mock-bin:$PATH"
  # shellcheck disable=SC1091 # The script loads its sibling bootstrap at runtime.
  source "$script_dir/bootstrap.sh"

  printf '%s\n' \
    preexisting-package \
    new-package \
    safe-obsolete \
    protected-obsolete \
    removable-obsolete \
    > "$root/generations/$generation/base-packages.txt"
  printf '%s\n' safe-obsolete > "$root/generations/$retained_generation/base-packages.txt"
  install_apt_packages "$root" "$generation"
  grep -Fxq new-package "$MOCK_INSTALLED_FILE"
  grep -Fxq safe-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq protected-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq removable-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq new-package "$root/apt-owned-packages.txt"
  assert_not_grep preexisting-package "$root/apt-owned-packages.txt"

  printf '%s\n' preexisting-package new-package > "$root/generations/$generation/base-packages.txt"
  remove_obsolete_apt_packages "$root"
  grep -Fxq safe-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq protected-obsolete "$MOCK_INSTALLED_FILE"
  assert_not_grep removable-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq safe-obsolete "$root/apt-owned-packages.txt"
  grep -Fxq protected-obsolete "$root/apt-owned-packages.txt"
  grep -Fxq new-package "$root/apt-owned-packages.txt"
  assert_not_grep removable-obsolete "$root/apt-owned-packages.txt"
  assert_not_grep preexisting-package "$root/apt-owned-packages.txt"
  grep -Fxq -- '-y remove -- removable-obsolete' "$MOCK_APT_LOG"
  assert_not_grep '-y remove -- safe-obsolete' "$MOCK_APT_LOG"
  assert_not_grep '-y remove -- protected-obsolete' "$MOCK_APT_LOG"
  assert_not_grep autoremove "$MOCK_APT_LOG"

  local newest_generation active_generation old_generation gc_output
  old_generation=$generation
  newest_generation=$(printf '%064d' 3)
  active_generation=$(printf '%064d' 4)
  mkdir -p "$root/generations/$newest_generation" "$root/generations/$active_generation"
  for generation in "$old_generation" "$retained_generation" "$newest_generation" "$active_generation"
  do
    printf '{}\n' > "$root/generations/$generation/manifest.json"
  done
  printf '%s\t%s\n' \
    1 "$old_generation" \
    2 "$retained_generation" \
    3 "$newest_generation" \
    4 "$active_generation" \
    > "$root/generation-index.tsv"
  printf '%s\n' obsolete-owned protected-obsolete > "$root/generations/$old_generation/base-packages.txt"
  printf '%s\n' retained-owned > "$root/generations/$retained_generation/base-packages.txt"
  printf '%s\n' retained-owned > "$root/generations/$newest_generation/base-packages.txt"
  printf '%s\n' current-owned > "$root/generations/$active_generation/base-packages.txt"
  ln -s "generations/$active_generation" "$root/current"
  printf '%s\n' obsolete-owned protected-obsolete retained-owned current-owned > "$root/apt-owned-packages.txt"
  printf '%s\n' obsolete-owned protected-obsolete retained-owned current-owned > "$MOCK_INSTALLED_FILE"

  gc_output=$(HOME="$temporary/home" bash "$script_dir/bootstrap.sh" gc --keep 3 --dry-run)
  grep -Fq "Would remove generation $old_generation" <<< "$gc_output"
  grep -Fq 'Would remove obsolete Termux APT package: obsolete-owned' <<< "$gc_output"
  [[ -d "$root/generations/$old_generation" ]]
  grep -Fxq obsolete-owned "$MOCK_INSTALLED_FILE"
  grep -Fxq obsolete-owned "$root/apt-owned-packages.txt"

  HOME="$temporary/home" bash "$script_dir/bootstrap.sh" gc --keep 3
  [[ ! -e "$root/generations/$old_generation" ]]
  [[ -d "$root/generations/$retained_generation" ]]
  [[ -d "$root/generations/$newest_generation" ]]
  [[ -d "$root/generations/$active_generation" ]]
  grep -Fxq retained-owned "$MOCK_INSTALLED_FILE"
  grep -Fxq current-owned "$MOCK_INSTALLED_FILE"
  grep -Fxq protected-obsolete "$MOCK_INSTALLED_FILE"
  assert_not_grep obsolete-owned "$MOCK_INSTALLED_FILE"
  assert_not_grep obsolete-owned "$root/apt-owned-packages.txt"
  grep -Fxq protected-obsolete "$root/apt-owned-packages.txt"
  [[ "$(wc -l < "$root/generation-index.tsv")" -eq 3 ]]
  assert_not_grep autoremove "$MOCK_APT_LOG"

  local symlink_generation
  symlink_generation=$(printf '%064d' 5)
  ln -s "$temporary/outside-generation" "$root/generations/$symlink_generation"
  if HOME="$temporary/home" bash "$script_dir/bootstrap.sh" gc --keep 3 >/dev/null 2>&1
  then
    printf 'Generation GC unexpectedly accepted a symlinked generation.\n' >&2
    return 1
  fi
  [[ -d "$root/generations/$active_generation" ]]
  grep -Fxq current-owned "$MOCK_INSTALLED_FILE"
  rm -- "$root/generations/$symlink_generation"

  printf 'PASS: APT ownership cleanup and generation GC retain rollback requirements, remove safe obsolete state, and block dependency cascades\n'
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
