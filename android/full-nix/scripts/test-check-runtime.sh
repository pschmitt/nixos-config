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

# Python fakes (shebang is the real interpreter, so the isolated PATH needs nothing
# else) for the Rust CLIs. NAME's behaviour is switched by a mode file next to the
# generation: ${0%/*}/../../fail-NAME holds segv, empty, wrong or a tool specific mode.
write_py_tool() {
  local dir="$1" name="$2" real
  real=$(readlink -f "$(command -v python3)")
  {
    printf '#!%s -I\n' "$real"
    cat
  } | write_tool "$dir" "$name"
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

  make_rust_cli_fakes "$dir"
}

make_rust_cli_fakes() {
  local dir="$1"
  write_py_tool "$dir" bat <<'FAKE'
import os, re, signal, sys
here = os.path.dirname(os.path.abspath(sys.argv[0]))
try:
    mode = open(os.path.join(here, '..', '..', 'fail-bat')).read().strip()
except OSError:
    mode = ''
if mode == 'segv':
    os.kill(os.getpid(), signal.SIGSEGV)
args = sys.argv[1:]
text = open(args[-1]).read()
if mode == 'empty':
    sys.exit(0)
if '--style=numbers' in args and '--decorations=always' in args:
    for i, line in enumerate(text.splitlines(), 1):
        print('%4d %s' % (i, line))
elif '--color=always' in args and mode != 'nocolor':
    for line in text.splitlines():
        print('\x1b[38;5;2m' + line + '\x1b[0m')
else:
    sys.stdout.write(text)
FAKE

  write_py_tool "$dir" rg <<'FAKE'
import os, re, signal, sys
here = os.path.dirname(os.path.abspath(sys.argv[0]))
try:
    mode = open(os.path.join(here, '..', '..', 'fail-rg')).read().strip()
except OSError:
    mode = ''
args = sys.argv[1:]
with open(os.path.join(here, '..', '..', 'seen-rg-cwd'), 'w') as f:
    f.write(os.getcwd() + '\n')
if mode == 'segv' or (mode == 'segv-pcre' and '-P' in args):
    os.kill(os.getpid(), signal.SIGSEGV)
if mode == 'nopcre' and '-P' in args:
    sys.stderr.write('PCRE2 is not available in this build\n')
    sys.exit(2)
if mode == 'empty':
    sys.exit(1)
flags, pos, i = set(), [], 0
while i < len(args):
    a = args[i]
    if a == '--sort':
        i += 1
    elif a.startswith('-'):
        flags.add(a)
    else:
        pos.append(a)
    i += 1
files_mode = '--files' in flags
if files_mode:
    root, pattern = pos[0], None
else:
    pattern, root = pos[0], pos[1]
paths = []
for d, dirs, names in os.walk(root):
    dirs.sort()
    for n in sorted(names):
        paths.append(os.path.join(d, n))
paths.sort()
if mode == 'wrong':
    paths = [p for p in paths if '/sub/' not in p]
if files_mode:
    print('\n'.join(paths))
    sys.exit(0 if paths else 1)
rx = re.compile(re.escape(pattern) if '-F' in flags else pattern,
                re.I if '-i' in flags else 0)
found = False
for path in paths:
    count = 0
    for n, line in enumerate(open(path).read().splitlines(), 1):
        ms = list(rx.finditer(line))
        if not ms:
            continue
        count += 1
        found = True
        if '-c' in flags or '-l' in flags:
            continue
        if '-o' in flags:
            for m in ms:
                print(m.group(0))
            continue
        prefix = '' if '--no-filename' in flags else path + ':'
        if '-N' not in flags:
            prefix += '%d:' % n
        print(prefix + line)
    if '-c' in flags and count:
        print('%s:%d' % (path, count))
    if '-l' in flags and count:
        print(path)
sys.exit(0 if found else 1)
FAKE

  write_py_tool "$dir" fd <<'FAKE'
import fnmatch, os, re, signal, sys
here = os.path.dirname(os.path.abspath(sys.argv[0]))
try:
    mode = open(os.path.join(here, '..', '..', 'fail-fd')).read().strip()
except OSError:
    mode = ''
with open(os.path.join(here, '..', '..', 'seen-fd-cwd'), 'w') as f:
    f.write(os.getcwd() + '\n')
if mode == 'segv':
    os.kill(os.getpid(), signal.SIGSEGV)
if mode == 'empty':
    sys.exit(0)
args = sys.argv[1:]
kind = ext = pattern = None
glob = hidden = False
i = 0
while i < len(args):
    a = args[i]
    if a == '-t':
        kind = args[i + 1]; i += 1
    elif a == '-e':
        ext = args[i + 1]; i += 1
    elif a == '-g':
        glob = True
    elif a == '-H':
        hidden = True
    elif a.startswith('-'):
        pass
    else:
        pattern = a
    i += 1
if mode == 'wrong':
    ext = None
out = []
for d, dirs, names in os.walk('.'):
    if not hidden:
        dirs[:] = [x for x in dirs if not x.startswith('.')]
    entries = [(x, True) for x in dirs] + [(x, False) for x in names]
    for name, isdir in entries:
        if not hidden and name.startswith('.'):
            continue
        if kind == 'f' and isdir or kind == 'd' and not isdir:
            continue
        if ext and not name.endswith('.' + ext):
            continue
        if pattern:
            if glob and not fnmatch.fnmatch(name, pattern):
                continue
            if not glob and not re.search(pattern, name):
                continue
        rel = os.path.relpath(os.path.join(d, name))
        out.append(rel + ('/' if isdir else ''))
print('\n'.join(out))
FAKE

  write_py_tool "$dir" rbw <<'FAKE'
import os, signal, sys
here = os.path.dirname(os.path.abspath(sys.argv[0]))
try:
    mode = open(os.path.join(here, '..', '..', 'fail-rbw')).read().strip()
except OSError:
    mode = ''
with open(os.path.join(here, '..', '..', 'seen-rbw-args'), 'w') as f:
    f.write(' '.join(sys.argv[1:]) + '\n')
with open(os.path.join(here, '..', '..', 'seen-rbw-home'), 'w') as f:
    f.write(os.environ.get('HOME', 'unset') + '\n')
if mode == 'segv':
    os.kill(os.getpid(), signal.SIGSEGV)
if sys.argv[1:] == ['version'] and mode != 'bad':
    print('rbw 2.46.0')
elif mode == 'bad':
    print('error: not logged in')
else:
    sys.exit(2)
FAKE

  write_py_tool "$dir" osc <<'FAKE'
import os, signal, sys
here = os.path.dirname(os.path.abspath(sys.argv[0]))
try:
    mode = open(os.path.join(here, '..', '..', 'fail-osc')).read().strip()
except OSError:
    mode = ''
with open(os.path.join(here, '..', '..', 'seen-osc-home'), 'w') as f:
    f.write(os.environ.get('HOME', 'unset') + '\n')
if mode == 'segv':
    os.kill(os.getpid(), signal.SIGSEGV)
if sys.argv[1:] == ['--version'] and mode != 'bad':
    print('osc 0.9.1')
elif mode == 'bad':
    print('usage: osc')
else:
    sys.exit(2)
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

# Breaks one fake with MODE and expects only that check to fail with a message
# containing TEXT. The good generation must pass again once the mode is removed.
expect_rust_cli_failure() {
  local tool="$1" mode="$2" text="$3"
  printf '%s\n' "$mode" > "$W/gen/fail-$tool"
  run_gate --isolated --generation "$W/gen"
  assert_eq 1 "$RC" "$tool $mode fails the gate"
  assert_contains "$W/out" "\"failed\": [\"$tool\"]" "$tool $mode: only $tool fails"
  assert_contains "$W/err" "$text" "$tool $mode message"
  rm -f "$W/gen/fail-$tool"
}

test_gate_rust_cli_good() {
  gate_world gate-rust-good
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "rust CLI checks pass with good fakes"
  assert_contains "$W/err" "PASS bat" "bat ran"
  assert_contains "$W/err" "PASS rg" "rg ran"
  assert_contains "$W/err" "incl. PCRE" "rg PCRE ran"
  assert_contains "$W/err" "PASS fd" "fd ran"
  assert_contains "$W/err" "PASS rbw (" "rbw ran"
  assert_contains "$W/err" "rbw 2.46.0" "rbw version reported"
  assert_contains "$W/err" "osc 0.9.1" "osc version reported"
  assert_eq version "$(cat "$W/gen/seen-rbw-args")" "rbw only runs the version command"
  assert_eq 0 "$(find "$W/scratch" -mindepth 1 | wc -l)" "rust CLI scratch removed"
}

test_gate_rust_cli_isolation() {
  local f
  gate_world gate-rust-isolation
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "isolated rust CLI run rc"
  for f in seen-rg-cwd seen-fd-cwd seen-rbw-home seen-osc-home
  do
    if [[ "$(cat "$W/gen/$f")" == "$W/scratch/"* ]]
    then
      ok
    else
      bad "$f is outside the scratch directory: $(cat "$W/gen/$f")"
    fi
  done
  # Active context: the real HOME must still not be visible to rbw and osc.
  gate_world gate-rust-active
  run_gate --generation "$W/gen" --only rbw --only osc --only rg --only fd \
    --config-dir "$W/gen/home-files/.config/nix"
  assert_eq 0 "$RC" "active rust CLI run rc"
  for f in seen-rbw-home seen-osc-home seen-rg-cwd seen-fd-cwd
  do
    if [[ "$(cat "$W/gen/$f")" == "$W/scratch/"* && "$(cat "$W/gen/$f")" != "$HOME"* ]]
    then
      ok
    else
      bad "active $f is outside the scratch directory: $(cat "$W/gen/$f")"
    fi
  done
}

test_gate_bat_regressions() {
  gate_world gate-bat
  expect_rust_cli_failure bat segv SIGSEGV
  expect_rust_cli_failure bat empty "bat plain printed nothing"
  expect_rust_cli_failure bat nocolor "no colour escapes"
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "bat passes again once repaired"
}

test_gate_rg_regressions() {
  gate_world gate-rg
  expect_rust_cli_failure rg segv SIGSEGV
  expect_rust_cli_failure rg segv-pcre "rg pcre: killed by SIGSEGV"
  expect_rust_cli_failure rg nopcre "rg pcre: exit 2"
  expect_rust_cli_failure rg empty "rg regex: exit 1"
  expect_rust_cli_failure rg wrong "unexpected output"
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "rg passes again once repaired"
}

test_gate_fd_regressions() {
  gate_world gate-fd
  expect_rust_cli_failure fd segv SIGSEGV
  expect_rust_cli_failure fd empty "fd extension printed nothing"
  expect_rust_cli_failure fd wrong "unexpected output"
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "fd passes again once repaired"
}

test_gate_rbw_osc_regressions() {
  gate_world gate-rbw-osc
  expect_rust_cli_failure rbw segv SIGSEGV
  expect_rust_cli_failure rbw bad "did not report a version"
  expect_rust_cli_failure osc segv SIGSEGV
  expect_rust_cli_failure osc bad "did not report a version"
  run_gate --isolated --generation "$W/gen"
  assert_eq 0 "$RC" "rbw and osc pass again once repaired"
}

test_gate_rust_cli_missing_tool() {
  local tool
  gate_world gate-rust-missing
  for tool in bat rg fd rbw osc
  do
    mv "$W/gen/home-path/bin/$tool" "$W/gen/$tool.off"
    run_gate --isolated --generation "$W/gen"
    assert_eq 1 "$RC" "missing $tool fails the gate"
    assert_contains "$W/out" "\"failed\": [\"$tool\"]" "only $tool fails"
    run_gate --isolated --generation "$W/gen" --skip "$tool"
    assert_eq 0 "$RC" "--skip $tool passes"
    mv "$W/gen/$tool.off" "$W/gen/home-path/bin/$tool"
  done
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
