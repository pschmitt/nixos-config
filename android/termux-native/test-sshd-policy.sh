#!/usr/bin/env bash

set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
export HOME="$temporary/home" PREFIX="$temporary/prefix"
generation="$temporary/generation"
config_dir="$PREFIX/etc/ssh/sshd_config.d"
payload_dir="$generation/home/.config/termux-native"
mkdir -p "$config_dir" "$PREFIX/bin" "$payload_dir" "$HOME"
printf 'Include sshd_config.d/*.conf\n' > "$PREFIX/etc/ssh/sshd_config"
cat > "$PREFIX/bin/sshd" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
config_dir="$PREFIX/etc/ssh/sshd_config.d"
if grep -q Invalid "$config_dir"/*.conf 2>/dev/null
then
  exit 1
fi
if [[ "$1" == -T ]]
then
  if [[ -f "$config_dir/nixpp-ports.conf" ]]
  then
    grep -i '^Port ' "$config_dir/nixpp-ports.conf"
  else
    printf 'port 8022\n'
  fi
  if [[ -f "$config_dir/nixpp-motd.conf" ]]
  then
    grep -i '^PrintMotd ' "$config_dir/nixpp-motd.conf"
  else
    printf 'printmotd yes\n'
  fi
fi
SH
chmod +x "$PREFIX/bin/sshd"

bash "$script_dir/setup-sshd.sh" "$generation"
[[ ! -e "$config_dir/nixpp-motd.conf" ]]
printf 'PASS: no optional payload is a no-op\n'
mkdir -p "$temporary/empty-switch"
ln -s next "$temporary/empty-switch/.next"
bash "$script_dir/setup-sshd.sh" "$generation" --switch-current "$temporary/empty-switch"
[[ "$(readlink "$temporary/empty-switch/current")" == next ]]
printf 'PASS: profiles without SSH policy can switch generations\n'

printf 'Port 8023\n' > "$config_dir/termuxpp-port.conf"
bash "$script_dir/setup-sshd.sh" "$generation"
grep -qx 'Port 8023' "$config_dir/termuxpp-port.conf"
printf 'PrintMotd no\n' > "$payload_dir/sshd-motd.conf"
bash "$script_dir/setup-sshd.sh" "$generation"
grep -qx 'Port 8023' "$config_dir/termuxpp-port.conf"
printf 'PASS: MOTD-only profiles preserve legacy ports\n'

printf 'Port 8023\n' > "$config_dir/termuxpp-port.conf"
printf 'Port 2222\n' > "$payload_dir/sshd-ports.conf"
printf 'PrintMotd no\n' > "$payload_dir/sshd-motd.conf"
bash "$script_dir/setup-sshd.sh" "$generation"
[[ ! -e "$config_dir/termuxpp-port.conf" ]]
grep -qx 'Port 2222' "$config_dir/nixpp-ports.conf"
grep -qx 'PrintMotd no' "$config_dir/nixpp-motd.conf"
[[ -f "$HOME/.local/share/termux-native/ssh-config-backups/termuxpp-port.conf" ]]
printf 'PASS: ports, MOTD and legacy migration\n'

cp "$config_dir/nixpp-ports.conf" "$temporary/ports-before"
cp "$config_dir/nixpp-motd.conf" "$temporary/motd-before"
printf 'Port 3333\n' > "$payload_dir/sshd-ports.conf"
printf 'Invalid\n' > "$payload_dir/sshd-motd.conf"
if bash "$script_dir/setup-sshd.sh" "$generation"
then
  printf 'Invalid SSH policy unexpectedly succeeded\n' >&2
  exit 1
fi
cmp "$temporary/ports-before" "$config_dir/nixpp-ports.conf"
cmp "$temporary/motd-before" "$config_dir/nixpp-motd.conf"
printf 'PASS: both drop-ins roll back together\n'

printf 'PrintMotd no\n' > "$payload_dir/sshd-motd.conf"
mkdir -p "$temporary/switch"
if bash "$script_dir/setup-sshd.sh" "$generation" --switch-current "$temporary/switch"
then
  printf 'Missing next generation unexpectedly switched\n' >&2
  exit 1
fi
cmp "$temporary/ports-before" "$config_dir/nixpp-ports.conf"
cmp "$temporary/motd-before" "$config_dir/nixpp-motd.conf"
ln -s old "$temporary/switch/current"
ln -s new "$temporary/switch/.next"
bash "$script_dir/setup-sshd.sh" "$generation" --switch-current "$temporary/switch"
[[ "$(readlink "$temporary/switch/current")" == new ]]
grep -qx 'Port 3333' "$config_dir/nixpp-ports.conf"
printf 'PASS: SSH policy rolls back on switch failure and commits on success\n'

rm "$payload_dir/sshd-ports.conf" "$payload_dir/sshd-motd.conf"
bash "$script_dir/setup-sshd.sh" "$generation"
[[ ! -e "$config_dir/nixpp-ports.conf" && ! -e "$config_dir/nixpp-motd.conf" ]]
printf 'PASS: removing options removes managed drop-ins\n'

printf '# user policy\nPort 4444\n' > "$config_dir/nixpp-ports.conf"
bash "$script_dir/setup-sshd.sh" "$generation"
grep -qx 'Port 4444' "$config_dir/nixpp-ports.conf"
printf 'Port 2222\n' > "$payload_dir/sshd-ports.conf"
if bash "$script_dir/setup-sshd.sh" "$generation"
then
  printf 'Unmanaged SSH policy unexpectedly overwritten\n' >&2
  exit 1
fi
grep -qx 'Port 4444' "$config_dir/nixpp-ports.conf"
rm "$config_dir/nixpp-ports.conf"
printf 'PASS: unmanaged policy is preserved\n'

printf 'PrintMotd no\n' > "$payload_dir/sshd-motd.conf"
bash "$script_dir/setup-sshd.sh" "$generation"
printf 'Invalid\n' > "$payload_dir/sshd-motd.conf"
# shellcheck source=android/termux-native/setup-sshd.sh
source "$script_dir/setup-sshd.sh"
mv() {
  if [[ "$*" == *ssh-config-backups/recovery.* ]]
  then
    return 1
  fi
  command mv "$@"
}
# shellcheck disable=SC2031
if setup_sshd "$generation"
then
  printf 'Failed rollback unexpectedly succeeded\n' >&2
  exit 1
fi
unset -f mv
recovery=("$HOME/.local/share/termux-native/ssh-config-backups"/recovery.*)
[[ -f "${recovery[0]}" ]]
printf 'PASS: failed rollback retains recovery files\n'

# shellcheck source=android/termux-native/activate.sh
source "$script_dir/activate.sh"
export PREFIX=/data/data/dev.pschmitt.termux/files/usr
mkdir -p "$generation/home/.config/termuxpp" "$HOME/.config/termuxpp"
printf '#!/system/bin/sh\n' > "$generation/home/.config/termuxpp/motd.sh"
printf 'custom MOTD\n' > "$HOME/.config/termuxpp/motd.sh"
link_termuxpp_motd "$generation"
grep -qx 'custom MOTD' "$HOME/.config/termuxpp/motd.sh"
rm "$HOME/.config/termuxpp/motd.sh"
link_termuxpp_motd "$generation"
[[ -L "$HOME/.config/termuxpp/motd.sh" ]]
rm "$generation/home/.config/termuxpp/motd.sh"
link_termuxpp_motd "$generation"
[[ ! -L "$HOME/.config/termuxpp/motd.sh" ]]
printf '#!/system/bin/sh\n' > "$generation/home/.config/termuxpp/motd.sh"
export PREFIX=/data/data/com.termux/files/usr
link_termuxpp_motd "$generation"
[[ ! -L "$HOME/.config/termuxpp/motd.sh" ]]
printf 'PASS: custom MOTD is preserved and stock Termux gets no fork link\n'

uname() { printf 'aarch64\n'; }
getprop() { printf '35\n'; }
check_host
export TERMUX_APP__DATA_DIR=/data/data/dev.pschmitt.termux
export PREFIX="$TERMUX_APP__DATA_DIR/files/usr"
if check_host
then
  printf 'Stock bundle accepted fork prefix\n' >&2
  exit 1
fi
printf 'PASS: stock bundle rejects fork runtime even with app environment set\n'

# vim: set ft=sh et ts=2 sw=2 :
