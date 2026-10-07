#!/usr/bin/env bash

main() (
  set -euo pipefail
  local script_dir temporary home root prefix bundle generation next_generation
  script_dir=$(dirname "${BASH_SOURCE[0]}")
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/termux-native-retry-test.XXXXXXXX")
  trap 'rm -rf -- "$temporary"' EXIT
  home="$temporary/home"
  root="$home/.local/share/termux-native"
  prefix="$temporary/prefix"
  next_generation=$(printf '%064d' 2)
  bundle="$temporary/environment.tar.gz"
  mkdir -p "$temporary/mock-bin" \
    "$home/.termux" "$prefix/etc" "$prefix/bin"
  printf 'test bundle\n' | gzip > "$bundle"
  generation=$(sha256sum "$bundle")
  generation=${generation%% *}
  mkdir -p "$root/generations/$generation"
  printf '%s\n' newly-installed-package > "$root/generations/$generation/base-packages.txt"
  : > "$temporary/installed-packages.txt"
  : > "$temporary/activation-attempts"
  : > "$temporary/apt.log"

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
  exit 0
fi
temporary=$(mktemp "$MOCK_INSTALLED_FILE.XXXXXXXX")
grep -Fxv -- "$package" "$MOCK_INSTALLED_FILE" > "$temporary" || true
mv -f -- "$temporary" "$MOCK_INSTALLED_FILE"
MOCK_APT_GET
  cat > "$temporary/mock-bin/chsh" <<'MOCK_CHSH'
#!/usr/bin/env bash
[[ "$1" == -s && "$2" == zsh ]]
MOCK_CHSH
  cat > "$temporary/activate.sh" <<'MOCK_ACTIVATE'
#!/usr/bin/env bash
set -euo pipefail
action=$1
generation=$3
case "$action" in
  preflight)
    exit 0
    ;;
  install)
    attempts=$(wc -l < "$ACTIVATION_ATTEMPTS")
    printf '%s\n' attempt >> "$ACTIVATION_ATTEMPTS"
    if ((attempts == 0))
    then
      printf 'Injected generation health-check failure\n' >&2
      exit 1
    fi
    root="$HOME/.local/share/termux-native"
    mkdir -p "$root/generations/$generation"
    printf '{}\n' > "$root/generations/$generation/manifest.json"
    printf '%s\n' newly-installed-package > "$root/generations/$generation/base-packages.txt"
    printf '# injected test zshenv\n' > "$root/generations/$generation/zshenv"
    printf '1\t%s\n' "$generation" > "$root/generation-index.tsv"
    ln -s "generations/$generation" "$root/.next"
    mv -Tf "$root/.next" "$root/current"
    ;;
  *)
    exit 2
    ;;
esac
MOCK_ACTIVATE
  cp -- "$script_dir/bootstrap.sh" "$temporary/bootstrap.sh"
  chmod +x "$temporary/mock-bin/"* "$temporary/activate.sh"
  export MOCK_INSTALLED_FILE="$temporary/installed-packages.txt"
  export MOCK_APT_LOG="$temporary/apt.log"
  export ACTIVATION_ATTEMPTS="$temporary/activation-attempts"
  export PATH="$temporary/mock-bin:$PATH"
  export HOME="$home"
  export PREFIX="$prefix"

  if bash "$temporary/bootstrap.sh" "$bundle" "$(sha256sum "$bundle" | cut -d ' ' -f1)"
  then
    printf 'Bootstrap unexpectedly passed its injected health-check failure.\n' >&2
    return 1
  fi
  grep -Fxq newly-installed-package "$MOCK_INSTALLED_FILE"
  grep -Fxq newly-installed-package "$root/apt-owned-packages.txt"
  [[ ! -e "$root/current" ]]
  [[ ! -e "$root/.lock" ]]

  bash "$temporary/bootstrap.sh" "$bundle" "$(sha256sum "$bundle" | cut -d ' ' -f1)"
  [[ "$(wc -l < "$MOCK_INSTALLED_FILE")" -eq 1 ]]
  grep -Fxq newly-installed-package "$root/apt-owned-packages.txt"
  [[ "$(wc -l < "$root/generation-index.tsv")" -eq 1 ]]

  mkdir -p "$root/generations/$next_generation"
  printf '{}\n' > "$root/generations/$next_generation/manifest.json"
  : > "$root/generations/$next_generation/base-packages.txt"
  printf '1\t%s\n2\t%s\n' "$generation" "$next_generation" > "$root/generation-index.tsv"
  ln -s "generations/$next_generation" "$root/.next"
  mv -Tf "$root/.next" "$root/current"
  bash "$temporary/bootstrap.sh" gc --keep 1
  [[ ! -e "$root/generations/$generation" ]]
  [[ -d "$root/generations/$next_generation" ]]
  if grep -Fxq newly-installed-package "$MOCK_INSTALLED_FILE"
  then
    printf 'GC retained an APT package no remaining generation requires.\n' >&2
    return 1
  fi
  if grep -Fxq newly-installed-package "$root/apt-owned-packages.txt"
  then
    printf 'GC retained the ownership record after removing the obsolete package.\n' >&2
    return 1
  fi
  grep -Fxq -- '-y remove -- newly-installed-package' "$MOCK_APT_LOG"
  printf 'PASS: activation failure preserves APT ownership for retry; successful retry activates; GC removes the package only after its generation is collected\n'
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
