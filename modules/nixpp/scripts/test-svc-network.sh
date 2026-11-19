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

for service in restricted free
do
  mkdir -p "$work/src/$service/log"
  printf '#!/bin/sh\nexec sleep 1000\n' >"$work/src/$service/run"
  printf '#!/bin/sh\nexec cat >/dev/null\n' >"$work/src/$service/log/run"
  chmod +x "$work/src/$service/run" "$work/src/$service/log/run"
done
jq -n --arg dir "$work/src" '{
  restricted: {enabled: true, allowedSsids: ["home"], directory: "\($dir)/restricted"},
  free: {enabled: true, allowedSsids: [], directory: "\($dir)/free"}
}' >"$work/services.json"

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

printf 'ok: svc Wi-Fi gating\n'
