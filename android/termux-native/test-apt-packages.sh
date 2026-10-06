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
  local script_dir temporary root generation
  script_dir=$(dirname "${BASH_SOURCE[0]}")
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/termux-native-apt-test.XXXXXXXX")
  trap 'rm -rf -- "$temporary"' EXIT
  root="$temporary/home/.local/share/termux-native"
  generation=$(printf '%064d' 1)
  mkdir -p "$temporary/mock-bin" "$root/generations/$generation"
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
    > "$root/generations/$generation/base-packages.txt"
  install_apt_packages "$root" "$generation"
  grep -Fxq new-package "$MOCK_INSTALLED_FILE"
  grep -Fxq safe-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq protected-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq new-package "$root/apt-owned-packages.txt"
  assert_not_grep preexisting-package "$root/apt-owned-packages.txt"

  printf '%s\n' preexisting-package new-package > "$root/generations/$generation/base-packages.txt"
  remove_obsolete_apt_packages "$root" "$generation"
  assert_not_grep safe-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq protected-obsolete "$MOCK_INSTALLED_FILE"
  grep -Fxq protected-obsolete "$root/apt-owned-packages.txt"
  grep -Fxq new-package "$root/apt-owned-packages.txt"
  assert_not_grep preexisting-package "$root/apt-owned-packages.txt"
  grep -Fxq -- '-y remove -- safe-obsolete' "$MOCK_APT_LOG"
  assert_not_grep '-y remove -- protected-obsolete' "$MOCK_APT_LOG"
  assert_not_grep autoremove "$MOCK_APT_LOG"
  printf 'PASS: preserves pre-existing APT packages, removes only owned obsolete packages, and blocks removal of dependents\n'
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
