#!/usr/bin/env bash
# Exercise `svc supervise` Wi-Fi gating with real runit.
# Needs bash, coreutils, jq, runit and util-linux (flock) on PATH, e.g.
#   nix shell nixpkgs#jq nixpkgs#runit nixpkgs#util-linux -c bash modules/nixpp/scripts/test-svc-network.sh

set -euo pipefail

svc_script=$(cd "$(dirname "$0")" && pwd)/svc.sh
work=$(mktemp -d)
supervisor_pid=

cleanup() {
  if [[ -n $supervisor_pid ]]
  then
    kill -TERM -- "-$supervisor_pid" 2>/dev/null || true
    wait "$supervisor_pid" 2>/dev/null || true
  fi
  pkill -f -- "runsvdir -P $work/" 2>/dev/null || true
  for directory in "$work"/state/services/*
  do
    [[ -d $directory ]] && sv exit "$directory" >/dev/null 2>&1 || true
  done
  sleep 0.5
  rm -rf -- "$work"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Any existing store path stands in for the selected generation.
generation=$(readlink -f "$(command -v bash)")
generation=${generation%/bin/bash}
[[ $generation =~ ^/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+._-]+$ ]] || fail "need bash from the Nix store"
name=${generation#/nix/store/}

mkdir -p "$work/runtime/system-candidates/$name" "$work/state"
printf '%s\n' "$name" >"$work/runtime/current-system"
printf '%s\n' "$generation" >"$work/runtime/system-candidates/$name/generation"

for service in restricted free filed
do
  mkdir -p "$work/src/$service/log"
  printf '#!/bin/sh\nexec sleep 1000\n' >"$work/src/$service/run"
  printf '#!/bin/sh\nexec cat >/dev/null\n' >"$work/src/$service/log/run"
  chmod +x "$work/src/$service/run" "$work/src/$service/log/run"
done
jq -n --arg dir "$work/src" '{
  restricted: {enabled: true, allowedSsids: ["home"], directory: "\($dir)/restricted"},
  free: {enabled: true, allowedSsids: [], directory: "\($dir)/free"},
  filed: {enabled: true, allowedSsids: [], allowedSsidsFile: "\($dir)/home-ssids",
    directory: "\($dir)/filed"}
}' >"$work/services.json"
# A secret file: CRLF line ends and blank lines are tolerated.
printf 'elsewhere\r\n\nhome\r\n' >"$work/src/home-ssids"

export NIXPP_SVC_MANIFEST=$work/services.json
export NIXPP_SVC_RUNTIME_DIR=$work/state
export NIXPP_SVC_SELECTOR=$work/runtime/current-system
export NIXPP_SVC_CURRENT_SYSTEM=$generation
export NIXPP_SVC_NETWORK=$work/runtime/network.json
export NIXPP_SVC_APK_LIBRARY=

svc() {
  bash "$svc_script" "$@"
}

status_of() {
  svc --json list | jq -r --arg name "$1" '.[] | select(.name == $name) | .status'
}

expect() {
  local service=$1 want=$2 attempt
  for ((attempt = 0; attempt < 50; attempt++))
  do
    [[ $(status_of "$service") == "$want" ]] && return 0
    sleep 0.2
  done
  fail "$service is $(status_of "$service"), expected $want ($3)"
}

network() {
  jq -n --arg ssid "$1" '{ssid: (if $ssid == "" then null else $ssid end)}' >"$NIXPP_SVC_NETWORK"
}

setsid bash "$svc_script" supervise >"$work/supervise.log" 2>&1 &
supervisor_pid=$!

expect free running "unrestricted service starts without network state"
cmp -s "$work/services.json" "$work/state/manifest.json" || fail "supervise did not publish the manifest for Tasker"
expect restricted down "no network state keeps the restricted service down"

network home
expect restricted running "allowed Wi-Fi starts it"
expect filed running "a name from the allow-list file starts it"
[[ $(svc --json show filed | jq -c '[.wifiRestricted, .allowedSsids, .configured.allowedSsids]') == '[true,["elsewhere","home"],["elsewhere","home"]]' ]] ||
  fail "show does not read the allow-list file: $(svc --json show filed)"
mv "$work/src/home-ssids" "$work/src/home-ssids.away"
expect filed down "an unreadable allow-list file allows no network"
mv "$work/src/home-ssids.away" "$work/src/home-ssids"
expect filed running "the restored file allows the network again"

network other
expect restricted down "another Wi-Fi stops it"
svc list >"$work/list.out"
grep -q 'restricted .*waiting for an allowed Wi-Fi network' "$work/list.out" || fail "list does not explain the stop"
if svc start restricted 2>"$work/start.err"
then
  fail "manual start on a disallowed network succeeded"
fi
grep -q 'may only run on its allowed Wi-Fi networks (current: other)' "$work/start.err" || fail "unclear start error"

network ""
expect restricted down "no Wi-Fi keeps it down"

network home
expect restricted running "returning to the allowed Wi-Fi starts it again"
touch -d '-10 minutes' "$NIXPP_SVC_NETWORK"
expect restricted down "stale network state stops it"

network home
expect restricted running "fresh state starts it again"
svc stop restricted
expect restricted down "manual stop"
sleep 2
[[ $(status_of restricted) == down ]] || fail "supervisor restarted a manually stopped service"
svc start restricted
expect restricted running "manual start on the allowed Wi-Fi"
expect free running "unrestricted service is unaffected throughout"

# svc show reports the process and where each setting comes from.
svc show free >"$work/show.txt"
grep -q 'status:        running (pid [0-9]*, up ' "$work/show.txt" || fail "show lacks the process: $(cat "$work/show.txt")"
grep -q 'start on boot: yes (configuration)' "$work/show.txt" || fail "show lacks start on boot"
grep -q 'wifi:          any network (configuration)' "$work/show.txt" || fail "show lacks the Wi-Fi setting"
[[ $(svc --json show restricted | jq -c '[.wifiRestricted, .allowedSsids, .network, (.pid > 0)]') == '[true,["home"],"allowed",true]' ]] ||
  fail "show --json is wrong: $(svc --json show restricted)"

# The app's services page changes the settings at run time.
settings=$work/state/settings.json
network other
expect restricted down "the configured restriction applies before any app setting"
printf '{"free":{"wifiRestricted":true,"allowedSsids":["home"]}}\n' >"$settings"
expect free down "the app restricts an unrestricted service"
svc --json list >"$work/list.json"
[[ $(jq -c '.[] | select(.name == "free") | [.allowedSsids, .ssidsOverridden, .network, .waitingForNetwork]' "$work/list.json") == '[["home"],true,"blocked",true]' ]] ||
  fail "list does not show the app setting: $(cat "$work/list.json")"
printf '{"free":{"wifiRestricted":false,"allowedSsids":["home"]}}\n' >"$settings"
expect free running "turning the restriction off keeps the list and restarts the service"
printf '{"restricted":{"wifiRestricted":false}}\n' >"$settings"
expect restricted running "the app lifts the configured restriction"
rm -f "$settings"
expect restricted down "the configured restriction applies again"
network home
expect restricted running "back on the allowed network"

# A tree whose native daemon dies retires instead of running unowned.
kill -TERM -- "-$supervisor_pid" 2>/dev/null || true
wait "$supervisor_pid" 2>/dev/null || true
for directory in "$work"/state/services/*; do sv -w 5 down "$directory" >/dev/null 2>&1 || true; done
sleep 1
sleep 300 &
owner=$!
NIXPP_SVC_OWNER_PID=$owner setsid bash "$svc_script" supervise >>"$work/supervise.log" 2>&1 &
supervisor_pid=$!
expect free running "a supervisor with a live owner starts the services"
kill "$owner"
for ((attempt = 0; attempt < 50; attempt++))
do
  kill -0 "$supervisor_pid" 2>/dev/null || break
  sleep 0.2
done
kill -0 "$supervisor_pid" 2>/dev/null && fail "the supervisor outlived its owner"
expect free down "the services stop with the retired supervisor"
supervisor_pid=

# Start on boot is separate from the Wi-Fi restriction.
printf '{"free":{"enabled":false}}\n' >"$work/state/settings.json"
setsid bash "$svc_script" supervise >>"$work/supervise.log" 2>&1 &
supervisor_pid=$!
expect restricted running "an enabled service starts on boot"
sleep 2
[[ $(status_of free) == down ]] || fail "a service with start on boot off was started"
svc start free
expect free running "it still starts by hand"
network other
expect restricted down "the restriction applies to services started on boot"
network home
expect restricted running "and restarts them when back"

printf 'ok: svc Wi-Fi gating, settings, show and owner retirement\n'
