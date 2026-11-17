#!/usr/bin/env bash

usage() {
  printf "Usage: %s [-h|--help]\nRun Android runtime acceptance scenarios with fake executables.\n" "$(basename "$0")"
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HERE/check-runtime.py"
PASS=0
FAIL=0
WORK=""
W=""
RC=0

ok() {
  PASS=$((PASS + 1))
}

bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

assert_eq() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" == "$got" ]]
  then
    ok
  else
    bad "$what: want '$want', got '$got'"
  fi
}

assert_contains() {
  local file="$1" text="$2" what="$3"
  if grep -q -F -- "$text" "$file"
  then
    ok
  else
    bad "$what: '$text' not in $file"
    sed 's/^/    /' "$file" >&2
  fi
}

write_tool() {
  local dir="$1" name="$2"
  cat > "$dir/home-path/bin/$name"
  chmod +x "$dir/home-path/bin/$name"
}

# Fakes are POSIX sh that use builtins only: the isolated PATH holds nothing but
# the generation's own bin directory. Markers next to the generation switch
# failure modes: ${0%/*}/../../NAME.
make_runtime_gen() {
  local dir="$1" real
  mkdir -p "$dir/home-path/bin" "$dir/home-files/.config/nix" \
    "$dir/home-files/.config/zsh-nix"
  real=$(readlink -f "$(command -v python3)")
  ln -s "$real" "$dir/home-path/bin/python3"
  printf 'export FOO=1\n' > "$dir/home-files/.config/zsh-nix/.zshenv"
  printf 'alias l=ls\n' > "$dir/home-files/.config/zsh-nix/.zshrc"
  printf 'experimental-features = nix-command flakes\nflake-registry =\n' \
    > "$dir/home-files/.config/nix/nix.conf"
  cat > "$dir/home-files/.config/nix/registry.json" <<'JSON'
{"version":2,"flakes":[{"exact":true,"from":{"id":"nixpkgs","type":"indirect"},"to":{"path":"/nix/store/abc-source","type":"path"}}]}
JSON

  write_tool "$dir" zsh <<'FAKE'
#!/bin/sh
if [ -e "${0%/*}/../../hang-zsh" ]; then
  while :; do :; done
fi
case "$*" in
  *-n*) exit 0 ;;
  *LOGIN*) echo FULLNIX-ZSH-LOGIN ;;
  *) echo FULLNIX-ZSH-5.9 ;;
esac
FAKE
  write_tool "$dir" nvim <<'FAKE'
#!/bin/sh
printf '%s\n' "$HOME" > "${0%/*}/../../seen-home"
printf '%s\n' "${SECRET_TOKEN:-unset}" > "${0%/*}/../../seen-secret"
printf '%s\n' "${FOO_PASS:-unset}" > "${0%/*}/../../seen-pass"
case "$*" in
  *NVIMCFG*) echo FULLNIX-NVIMCFG-0 ;;
  *) echo FULLNIX-NVIM-0 ;;
esac
FAKE
  write_tool "$dir" eza <<'FAKE'
#!/bin/sh
if [ -e "${0%/*}/../../fail-eza" ]; then
  kill -SEGV $$
fi
echo listing
FAKE
  write_tool "$dir" git <<'FAKE'
#!/bin/sh
exit 0
FAKE
  write_tool "$dir" nix <<'FAKE'
#!/bin/sh
case "$*" in
  *--version*) echo "nix (Nix) 2.30.0" ;;
  *registry*)
    echo "user   flake:nixpkgs path:/nix/store/abc-source?narHash=sha256-x"
    if [ -e "${0%/*}/../../global-registry" ]; then
      echo "global flake:agda github:agda/agda"
    fi
    if [ -e "${0%/*}/../../local-global-registry" ]; then
      echo "global flake:nixpkgs path:/nix/store/abc-source"
    fi
    ;;
  *) exit 1 ;;
esac
FAKE
  write_tool "$dir" tmux <<'FAKE'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -S|-f) shift 2 ;;
    *) break ;;
  esac
done
if [ "$1" = list-sessions ]; then
  echo fnx
fi
exit 0
FAKE
  write_tool "$dir" kubectl <<'FAKE'
#!/bin/sh
case "$*" in
  *"version --client --output=json"*)
    if [ -e "${0%/*}/../../kubectl-bad-platform" ]; then
      plat=linux/amd64
    else
      plat=linux/arm64
    fi
    printf '%s\n' "${KUBECONFIG:-unset}" > "${0%/*}/../../seen-kubeconfig"
    if [ -e "${0%/*}/../../kubectl-bad-json" ]; then
      echo 'not json'
    else
      printf '{"clientVersion":{"gitVersion":"v1.33.1","platform":"%s"}}\n' "$plat"
    fi
    ;;
  *) exit 1 ;;
esac
FAKE
}

run_gate() {
  RC=0
  env SECRET_TOKEN=hunter2 FOO_PASS=passed \
    timeout 120 python3 -I "$CHECKER" --scratch-base "$W/scratch" \
    --timeout 3 --login-timeout 3 --total-timeout 60 "$@" \
    > "$W/out" 2> "$W/err" || RC=$?
}

gate_world() {
  W="$WORK/$1"
  mkdir -p "$W/scratch"
  make_runtime_gen "$W/gen"
}

test_gate_good() {
  gate_world gate-good
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "gate passes a good candidate"
  assert_contains "$W/out" '"success": true' "gate json success"
  assert_contains "$W/out" '"context": "candidate"' "gate context"
  assert_contains "$W/err" "PASS eza" "eza ran"
  assert_contains "$W/err" "PASS go" "kubectl client check ran"
  assert_contains "$W/err" "PASS tmux" "tmux ran"
  assert_eq "0" "$(find "$W/scratch" -mindepth 1 | wc -l)" "scratch directory removed"
}

test_gate_isolation() {
  gate_world gate-isolation
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "isolation run rc"
  if [[ "$(cat "$W/gen/seen-home")" == "$W/scratch/"* && "$(cat "$W/gen/seen-home")" != "$HOME" ]]
  then
    ok
  else
    bad "isolated HOME is not in the scratch directory: $(cat "$W/gen/seen-home")"
  fi
  assert_eq unset "$(cat "$W/gen/seen-secret")" "secret variable scrubbed"
  assert_eq unset "$(cat "$W/gen/seen-pass")" "unlisted variable scrubbed"
  gate_world gate-pass-env
  RC=0
  env FOO_PASS=passed FULL_NIX_PASS_ENV='FOO_*' \
    timeout 120 python3 -I "$CHECKER" --scratch-base "$W/scratch" --timeout 3 \
    --total-timeout 60 --isolated --generation "$W/gen" \
    > "$W/out" 2> "$W/err" || RC=$?
  assert_eq 0 "$RC" "pass-env run rc"
  assert_eq passed "$(cat "$W/gen/seen-pass")" "FULL_NIX_PASS_ENV passes variables"
}

test_gate_eza_crash() {
  gate_world gate-eza
  : > "$W/gen/fail-eza"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "eza crash fails the gate"
  assert_contains "$W/out" '"failed": ["eza"]' "only eza fails"
  assert_contains "$W/err" "SIGSEGV" "signal reported"
}

test_gate_nix_remote() {
  gate_world gate-nix-local-global
  : > "$W/gen/local-global-registry"
  printf 'experimental-features = nix-command flakes\nflake-registry = file:///nix/store/abc-registry.json\n' \
    > "$W/gen/home-files/.config/nix/nix.conf"
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "immutable local global registry passes the gate"
  : > "$W/gen/global-registry"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "remote entry fails even with local global registry configured"

  gate_world gate-nix-global
  : > "$W/gen/global-registry"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "global registry fails the gate"
  assert_contains "$W/out" '"failed": ["nix"]' "only nix fails"

  gate_world gate-nix-remote-entry
  cat > "$W/gen/home-files/.config/nix/registry.json" <<'JSON'
{"version":2,"flakes":[{"exact":true,"from":{"id":"nixpkgs","type":"indirect"},"to":{"owner":"NixOS","repo":"nixpkgs","type":"github"}}]}
JSON
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "remote registry entry fails the gate"
  assert_contains "$W/err" "not a local path" "remote entry message"

  gate_world gate-nix-no-flake-registry
  printf 'experimental-features = nix-command flakes\n' \
    > "$W/gen/home-files/.config/nix/nix.conf"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "unset flake-registry fails the gate"
  assert_contains "$W/err" "flake-registry is unset" "flake-registry message"
}

test_gate_missing_tool() {
  gate_world gate-no-kubectl
  rm "$W/gen/home-path/bin/kubectl"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "missing kubectl fails the gate"
  assert_contains "$W/out" '"failed": ["go"]' "only the go check fails"
  run_gate --isolated --generation "$W/gen" --skip go
  assert_eq 0 "$RC" "--skip go passes"
  assert_contains "$W/err" "SKIP go" "skip reported"
}

test_gate_kubectl_client_only() {
  gate_world gate-kubectl-platform
  : > "$W/gen/kubectl-bad-platform"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "wrong kubectl platform fails the gate"
  assert_contains "$W/err" "expected linux/arm64" "platform message"
  run_gate --isolated --generation "$W/gen" --expect-arch amd64
  assert_eq 0 "$RC" "--expect-arch overrides the platform"

  gate_world gate-kubectl-json
  : > "$W/gen/kubectl-bad-json"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "invalid kubectl json fails the gate"
  assert_contains "$W/err" "clientVersion.gitVersion" "json message"

  gate_world gate-kubectl-env
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "kubectl gate rc"
  if [[ "$(cat "$W/gen/seen-kubeconfig")" == "$W/scratch/"* ]]
  then
    ok
  else
    bad "kubectl saw a real kubeconfig: $(cat "$W/gen/seen-kubeconfig")"
  fi
}

test_gate_hang_is_bounded() {
  local start end
  gate_world gate-hang
  : > "$W/gen/hang-zsh"
  start=$SECONDS
  run_gate --isolated --generation "$W/gen"
  end=$SECONDS
  assert_eq 1 "$RC" "hung zsh fails the gate"
  assert_contains "$W/out" '"failed": ["zsh"]' "only zsh fails"
  assert_contains "$W/err" "timed out" "timeout reported"
  if (( end - start < 40 ))
  then
    ok
  else
    bad "hung check was not bounded: $((end - start))s"
  fi
}

test_gate_active_and_list() {
  gate_world gate-active
  run_gate --generation "$W/gen" --config-dir "$W/gen/home-files/.config/nix"
  assert_eq 0 "$RC" "active gate rc"
  assert_contains "$W/out" '"context": "active"' "active context"
  assert_contains "$W/err" "login shell ok" "login shell exercised"
  run_gate --list
  assert_contains "$W/out" "sockets" "--list shows checks"
  run_gate --isolated
  assert_eq 2 "$RC" "--isolated without --generation is a usage error"
}

# --- driver -----------------------------------------------------------------

cleanup() {
  if [[ -n "$WORK" ]]
  then
    rm -rf "$WORK"
  fi
}

main() {
  local test_name
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
  esac
  if [[ -z "${FULL_NIX_TEST_BOUNDED:-}" ]]
  then
    FULL_NIX_TEST_BOUNDED=1 exec timeout 600 bash "${BASH_SOURCE[0]}" "$@"
  fi
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/fnxt.XXXXXX") || return 1
  trap cleanup EXIT
  for test_name in $(compgen -A function test_)
  do
    "$test_name"
  done
  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ "$FAIL" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
