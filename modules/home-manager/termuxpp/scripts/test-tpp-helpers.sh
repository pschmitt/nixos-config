#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export NIXPP_RUNTIME=$tmp
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/tpp-am"
chmod +x "$tmp/bin/tpp-am"
export PATH="$tmp/bin:$PATH"
printf '{"phase":"UP_TO_DATE","installed":"abc","updated":%s}\n' "$(date +%s)" > "$tmp/update-status.json"
printf '{"updated":%s,"shizuku":"READY","runtime":{"android.permission.CAMERA":true},"special":{}}\n' "$(date +%s)" > "$tmp/permissions.json"

bash "$root/self-update.sh" status --json | jq -e '.phase == "UP_TO_DATE"' >/dev/null
bash "$root/self-update.sh" status | grep -q 'installed: abc'
bash "$root/self-update.sh" __complete sta | grep -qx status
bash "$root/setup-permissions.sh" status --no-shizuku --json | jq -e '.permissions[0].name == "CAMERA" and .permissions[0].state == "granted"' >/dev/null
bash "$root/setup-permissions.sh" __complete gr | grep -qx grant
bash "$root/self-update.sh" cancel --json | jq -e '.command == "cancel" and .exitCode == 0' >/dev/null
bash "$root/setup-permissions.sh" grant CAMERA --no-shizuku --json | jq -e '.command == "grant" and .exitCode == 0' >/dev/null
status=0
bash "$root/setup-permissions.sh" grant 2>"$tmp/grant-error" || status=$?
[[ $status == 2 ]]
grep -q -- '--all' "$tmp/grant-error"
status=0
bash "$root/app.sh" restart 2>"$tmp/restart-error" || status=$?
[[ $status == 2 ]]
grep -q -- '--yes' "$tmp/restart-error"
bash "$root/app.sh" restart --help | grep -q '^Usage: tpp app restart --yes$'
printf 'tpp helper tests passed\n'

# vim: set ft=sh et ts=2 sw=2 :
