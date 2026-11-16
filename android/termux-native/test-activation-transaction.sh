#!/usr/bin/env bash

main() (
  set -euo pipefail
  local script_dir temporary root old candidate generation output
  script_dir=$(dirname "${BASH_SOURCE[0]}")
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/termux-native-activation-test.XXXXXXXX")
  trap 'rm -rf -- "$temporary"' EXIT
  export HOME="$temporary/home" PREFIX="$temporary/prefix"
  root="$HOME/.local/share/termux-native"
  old=$(printf '%064d' 1)
  candidate=$(printf '%064d' 2)
  generation="$root/generations/$candidate"
  mkdir -p "$generation/bin" "$generation/shell" "$PREFIX/bin" \
    "$PREFIX/etc/ssh/ssh_known_hosts.d" "$PREFIX/etc/ssh/ssh_config.d" \
    "$root/generations/$old"
  ln -s "generations/$old" "$root/current"
  ln -s "$(command -v bash)" "$PREFIX/bin/bash"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$PREFIX/bin/zsh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$generation/bin/termux-nix-hello"
  chmod +x "$PREFIX/bin/zsh" "$generation/bin/termux-nix-hello"
  : > "$generation/base-packages.txt"
  : > "$generation/shell/check-pty.zsh"
  cat > "$generation/setup-known-hosts.sh" <<'KNOWN_HOSTS'
#!/usr/bin/env bash
printf 'candidate hosts\n' > "$PREFIX/etc/ssh/ssh_known_hosts.d/nixpp"
printf 'candidate config\n' > "$PREFIX/etc/ssh/ssh_config.d/nixpp.conf"
KNOWN_HOSTS
  cat > "$generation/setup-gpg-keys.sh" <<'GPG_KEYS'
#!/usr/bin/env bash
[[ "$(readlink -f "$HOME/.local/share/termux-native/current")" == "$1" ]] || exit 2
printf 'imported\n' > "$HOME/gpg-imported"
exit 1
GPG_KEYS
  printf '#!/usr/bin/env bash\nexit 1\n' > "$generation/setup-sshd.sh"
  printf 'original hosts\n' > "$PREFIX/etc/ssh/ssh_known_hosts.d/nixpp"
  printf 'original config\n' > "$PREFIX/etc/ssh/ssh_config.d/nixpp.conf"
  # shellcheck disable=SC1091 # The test sources its sibling activation script.
  source "$script_dir/activate.sh"

  if switch_generation "$root" "$candidate" install
  then
    printf 'Activation unexpectedly succeeded with invalid SSH server policy.\n' >&2
    return 1
  fi
  [[ "$(readlink "$root/current")" == "generations/$old" ]]
  grep -Fxq 'original hosts' "$PREFIX/etc/ssh/ssh_known_hosts.d/nixpp"
  grep -Fxq 'original config' "$PREFIX/etc/ssh/ssh_config.d/nixpp.conf"
  [[ ! -e "$HOME/gpg-imported" ]]
  rm -f "$root/.next"

  rm "$PREFIX/etc/ssh/ssh_known_hosts.d/nixpp" "$PREFIX/etc/ssh/ssh_config.d/nixpp.conf"
  if switch_generation "$root" "$candidate" install
  then
    printf 'Activation unexpectedly succeeded with invalid SSH server policy.\n' >&2
    return 1
  fi
  [[ ! -e "$PREFIX/etc/ssh/ssh_known_hosts.d/nixpp" ]]
  [[ ! -e "$PREFIX/etc/ssh/ssh_config.d/nixpp.conf" ]]
  [[ ! -e "$HOME/gpg-imported" ]]
  rm -f "$root/.next" "$generation/setup-sshd.sh"

  output=$(switch_generation "$root" "$candidate" install 2>&1)
  [[ "$(readlink "$root/current")" == "generations/$candidate" ]]
  [[ -e "$HOME/gpg-imported" ]]
  grep -Fq 'generation activated, but GPG key provisioning failed' <<< "$output"
  grep -Fxq 'candidate hosts' "$PREFIX/etc/ssh/ssh_known_hosts.d/nixpp"
  grep -Fxq 'candidate config' "$PREFIX/etc/ssh/ssh_config.d/nixpp.conf"
  printf 'PASS: failed activation restores SSH client state; GPG provisioning follows a successful switch\n'
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
