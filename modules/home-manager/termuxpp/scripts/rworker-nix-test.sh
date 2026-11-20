#!/usr/bin/env bash
# Unit tests for rworker-nix.sh. Everything external (rworker, ssh, nix) is a
# fake on PATH, so no worker is leased and nothing is built. Each scenario
# runs the wrapper in its own bash process (with errexit, nounset and pipefail
# like writeShellApplication), bounded by timeout(1).
#
# The fake controller answers like the real rworker client: `up --json` gives
# name, ip, ips and host_key; `builder` prints the 8-field Nix machines line
# with x86_64-linux and the base64 host key.

usage() {
  cat <<EOF
Usage: $(basename "$0") [-h|--help]

Run the rworker-nix.sh scenarios against fake rworker, ssh and nix commands.
EOF
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/rworker-nix.sh"
PASS=0
FAIL=0
WORK=""

# Writes the fake rworker, ssh and nix commands into $WORK/bin.
make_fakes() {
  mkdir -p "$WORK/bin"

  cat > "$WORK/bin/rworker" <<'FAKE'
#!/usr/bin/env bash
printf 'rworker %s\n' "$*" >> "$FAKE_TRACE"
[[ "${1:-}" != up ]] || printf 'RWORKER_AWS_CREDENTIALS_FILE=%s\n' "${RWORKER_AWS_CREDENTIALS_FILE:-}" >> "$FAKE_TRACE"
hostkey='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItestkeytestkeytestkeytestkeytest'
action="${1:-}"
shift
case "$action" in
  up)
    while [[ $# -gt 0 ]]
    do
      if [[ "$1" == --topic ]]
      then
        printf '%s' "$2" > "$FAKE_DIR/topic"
      fi
      shift
    done
    if [[ "$FAKE_SCENARIO" == up-fails* ]]
    then
      exit 1
    fi
    printf '{"name":"w-test1","ip":"100.64.0.7","ips":{"netbird":"100.64.0.7","tailscale":"100.100.0.7"},"host_key":"%s","expires_at":"x","flavor":"f"}\n' "$hostkey"
    ;;
  builder)
    key=$(printf '%s\n' "$hostkey" | base64 -w0)
    ip=100.64.0.7
    [[ "$FAKE_SCENARIO" != builder-wrong-ip ]] || ip=10.9.9.9
    [[ "$FAKE_SCENARIO" != builder-no-newline ]] || key=$(printf '%s' "$hostkey" | base64 -w0)
    [[ "$FAKE_SCENARIO" != builder-bad-base64 ]] || key='!!notbase64!!'
    [[ "$FAKE_SCENARIO" != builder-wrong-key ]] || key=$(printf 'ssh-ed25519 AAAAevil\n' | base64 -w0)
    sys=x86_64-linux
    [[ "$FAKE_SCENARIO" != native ]] || sys=aarch64-linux
    printf 'ssh-ng://agent@%s %s /home/u/.ssh/id_ed25519 16 1 nixos-test,benchmark,big-parallel,kvm - %s' "$ip" "$sys" "$key"
    ;;
  ssh)
    printf 'rworker-ssh-command %s\n' "$2" >> "$FAKE_TRACE"
    if [[ "$2" == nix\ build* ]]
    then
      case "$FAKE_SCENARIO" in
        remote-bad-output) printf 'warning: something\n' ;;
        remote-no-output) ;;
        remote-build-fails) exit 3 ;;
        *) printf '/nix/store/aaaa-system-a\n/nix/store/bbbb-system-b\n' ;;
      esac
      exit 0
    fi
    case "$FAKE_SCENARIO" in
      ssh-never-ready)
        exit 255
        ;;
      no-extra-platforms)
        printf 'system=x86_64-linux\nextra=\nbinfmt=enabled\n'
        ;;
      no-binfmt)
        printf 'system=x86_64-linux\nextra=aarch64-linux\nbinfmt=\n'
        ;;
      native)
        printf 'system=aarch64-linux\nextra=\nbinfmt=\n'
        ;;
      *)
        printf 'system=x86_64-linux\nextra=aarch64-linux i686-linux\nbinfmt=enabled\n'
        ;;
    esac
    ;;
  ls)
    if [[ "$FAKE_SCENARIO" == up-fails-leaked && -r "$FAKE_DIR/topic" ]]
    then
      jq -n --arg t "$(cat "$FAKE_DIR/topic")" \
        '[{name:"w-leaked",kind:"adhoc",topic:$t},{name:"w-other",kind:"adhoc",topic:"someone else"}]'
    else
      printf '[]\n'
    fi
    ;;
  down)
    [[ "$FAKE_SCENARIO" != down-fails ]] || exit 1
    ;;
  *)
    printf 'unexpected rworker action %s\n' "$action" >&2
    exit 99
    ;;
esac
FAKE

  cat > "$WORK/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
printf 'ssh %s\n' "$*" >> "$FAKE_TRACE"
if [[ "$1" == -G ]]
then
  printf 'hostname controller.invalid\n'
  case "$FAKE_SCENARIO" in
    strict-no) printf 'stricthostkeychecking false\n' ;;
    strict-accept-new) printf 'stricthostkeychecking accept-new\n' ;;
    *) printf 'stricthostkeychecking ask\n' ;;
  esac
  exit 0
fi
printf 'unexpected ssh call\n' >&2
exit 99
FAKE

  cat > "$WORK/bin/nix" <<'FAKE'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$FAKE_TRACE"
printf 'NIX_SSHOPTS=%s\n' "$NIX_SSHOPTS" >> "$FAKE_TRACE"
if [[ "$1 $2" == "flake metadata" ]]
then
  [[ "$FAKE_SCENARIO" != remote-lock-fails ]] || exit 1
  for arg
  do
    flake="$arg"
  done
  # No path: metadata's path is not in the store yet (git cache); the
  # script must take the source from flake prefetch.
  jq -n --arg flake "$flake" '{url: ($flake + "/locked-rev?narHash=sha256-x"),
    locks: {nodes: {
      root: {inputs: {pub: "pub", priv: "priv"}},
      pub: {locked: {type: "github", owner: "o", repo: "pub", rev: "r1"}},
      priv: {locked: {type: "gitlab", owner: "o", repo: "priv", rev: "r2", dir: "sub"}}
    }}}'
  exit 0
fi
if [[ "$1 $2" == "flake prefetch" ]]
then
  printf '{"storePath": "/nix/store/src-top"}\n'
  exit 0
fi
if [[ "$1" == eval ]]
then
  if [[ "$LOCKED" == *'"dir"'* ]]
  then
    exit 9
  fi
  case "$LOCKED" in
    *'"repo":"pub"'*) printf '/nix/store/src-pub' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
case "$FAKE_SCENARIO" in
  nix-fails)
    exit 7
    ;;
  nix-term)
    kill -TERM "$PPID"
    exit 0
    ;;
esac
exit 0
FAKE

  chmod +x "$WORK/bin/rworker" "$WORK/bin/ssh" "$WORK/bin/nix"
}

# run_scenario SCENARIO [ARGS...]; sets RC, ERR and TRACE.
run_scenario() {
  local scenario="$1"
  shift
  rm -f "$WORK/trace" "$WORK/topic"
  : > "$WORK/trace"
  RC=0
  env -i \
    PATH="$WORK/bin:$PATH_BASE" \
    HOME="$WORK/home" \
    XDG_CONFIG_HOME="$WORK/home/.config" \
    FAKE_SCENARIO="$scenario" \
    FAKE_TRACE="$WORK/trace" \
    FAKE_DIR="$WORK" \
    RWORKER_NIX_SSH_ATTEMPTS=2 \
    RWORKER_NIX_RETRY_DELAY=0 \
    RWORKER_NIX_CONTROLLER=ctl \
    ${SCENARIO_ENV:+"$SCENARIO_ENV"} \
    timeout 60 bash -euo pipefail "$SCRIPT" "$@" > "$WORK/out" 2> "$WORK/err" || RC=$?
  ERR=$(< "$WORK/err")
  TRACE=$(< "$WORK/trace")
}

pass() {
  PASS=$((PASS + 1))
  printf 'ok   %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s: %s\n' "$1" "$2"
  printf -- '--- stderr\n%s\n--- trace\n%s\n---\n' "$ERR" "$TRACE"
}

expect_rc() {
  local name="$1" want="$2"
  if [[ "$RC" != "$want" ]]
  then
    fail "$name" "exit code $RC, wanted $want"
    return 1
  fi
}

expect_trace() {
  local name="$1" needle="$2"
  if [[ "$TRACE" != *"$needle"* ]]
  then
    fail "$name" "trace lacks '$needle'"
    return 1
  fi
}

expect_no_trace() {
  local name="$1" needle="$2"
  if [[ "$TRACE" == *"$needle"* ]]
  then
    fail "$name" "trace has unexpected '$needle'"
    return 1
  fi
}

expect_err() {
  local name="$1" needle="$2"
  if [[ "$ERR" != *"$needle"* ]]
  then
    fail "$name" "stderr lacks '$needle'"
    return 1
  fi
}

# A scenario in which no worker is ever leased.
expect_no_lease() {
  expect_no_trace "$1" 'rworker up' && expect_no_trace "$1" 'NIX_SSHOPTS='
}

test_success_emulated() {
  local n=success-emulated
  run_scenario ok --system aarch64-linux build '.#hello' --print-out-paths
  expect_rc "$n" 0 \
    && expect_trace "$n" 'rworker up --json --ttl 1h --topic full-nix rworker-nix build rwn-' \
    && expect_trace "$n" 'nix build --max-jobs 0 --builders ssh-ng://agent@100.64.0.7 aarch64-linux ' \
    && expect_trace "$n" '--option builders-use-substitutes true .#hello --print-out-paths' \
    && expect_trace "$n" 'NIX_SSHOPTS=-o StrictHostKeyChecking=yes' \
    && expect_trace "$n" 'head -n 1 /proc/sys/fs/binfmt_misc/aarch64-linux 2>/dev/null || head -n 1 /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null' \
    && expect_trace "$n" 'rworker down w-test1' \
    && expect_no_trace "$n" 'accept-new' \
    && expect_no_trace "$n" 'StrictHostKeyChecking=no' \
    && pass "$n"
}

test_default_system_and_options() {
  local n=default-options
  run_scenario ok --ttl 30m --topic eza --profile standard --disk 80 shell nixpkgs#eza
  expect_rc "$n" 0 \
    && expect_trace "$n" 'rworker up --json --ttl 30m --topic full-nix rworker-nix eza rwn-' \
    && expect_trace "$n" '--profile standard --disk 80' \
    && expect_trace "$n" 'nix shell --max-jobs 0 --builders ssh-ng://agent@100.64.0.7 aarch64-linux ' \
    && pass "$n"
}

test_builder_key_is_pinned_key() {
  local n=builder-line-key
  run_scenario ok develop
  expect_rc "$n" 0 \
    && expect_trace "$n" ' - c3NoLWVkMjU1MTkgQUFBQUM' \
    && pass "$n"
}

test_native_worker() {
  local n=native-worker
  run_scenario native build '.#x'
  expect_rc "$n" 0 \
    && expect_trace "$n" 'nix build --max-jobs 0 --builders ssh-ng://agent@100.64.0.7 aarch64-linux ' \
    && pass "$n"
}

test_nix_failure_keeps_status_and_cleans_up() {
  local n=nix-fails
  run_scenario nix-fails build '.#x'
  expect_rc "$n" 7 \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_term_signal_cleans_up() {
  local n=nix-term
  run_scenario nix-term build '.#x'
  expect_rc "$n" 143 \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_no_binfmt() {
  local n=no-binfmt
  run_scenario no-binfmt build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'binfmt' \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_no_extra_platforms() {
  local n=no-extra-platforms
  run_scenario no-extra-platforms build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'extra-platforms' \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_ssh_never_ready() {
  local n=ssh-never-ready
  run_scenario ssh-never-ready build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'pinned host key' \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_host_key_mismatch() {
  local n=builder-wrong-key
  run_scenario builder-wrong-key build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'host key does not match' \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_host_key_encoding_variants() {
  local n
  n=builder-no-newline
  run_scenario builder-no-newline build '.#x'
  expect_rc "$n" 0 && pass "$n"
  n=builder-bad-base64
  run_scenario builder-bad-base64 build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'host key does not match' \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && pass "$n"
}

test_builder_address_mismatch() {
  local n=builder-wrong-ip
  run_scenario builder-wrong-ip build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'not an address of worker' \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && expect_trace "$n" 'rworker down w-test1' \
    && pass "$n"
}

test_up_fails_finds_leaked_worker() {
  local n=up-fails-leaked
  run_scenario up-fails-leaked build '.#x'
  expect_rc "$n" 1 \
    && expect_no_trace "$n" 'nix build --max-jobs' \
    && expect_trace "$n" 'rworker ls --json' \
    && expect_trace "$n" 'rworker down w-leaked' \
    && expect_no_trace "$n" 'rworker down w-other' \
    && pass "$n"
}

test_up_fails_nothing_to_clean() {
  local n=up-fails
  run_scenario up-fails build '.#x'
  expect_rc "$n" 1 \
    && expect_no_trace "$n" 'rworker down' \
    && pass "$n"
}

test_down_failure_is_reported() {
  local n=down-fails
  run_scenario down-fails build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" '--down w-test1' \
    && pass "$n"
}

test_strict_host_key_config_refused() {
  local n
  for n in strict-no strict-accept-new
  do
    run_scenario "$n" build '.#x'
    expect_rc "$n" 1 \
      && expect_err "$n" 'StrictHostKeyChecking' \
      && expect_no_lease "$n" \
      && pass "$n"
  done
}

test_nix_sshopts_refused() {
  local n=nix-sshopts-no
  SCENARIO_ENV='NIX_SSHOPTS=-o StrictHostKeyChecking=accept-new' run_scenario ok build '.#x'
  expect_rc "$n" 1 \
    && expect_err "$n" 'NIX_SSHOPTS' \
    && expect_no_lease "$n" \
    && pass "$n"
}

test_conflicting_nix_args_refused() {
  local n arg
  for arg in --builders --max-jobs -j --store --max-jobs=4 -j4 -Lj4 --builders= \
    --builders=x --extra-builders=x --extra-builders --no-builders-use-substitutes \
    --store=x --eval-store=x --option=max-jobs --option=builders=x
  do
    n="conflict$arg"
    run_scenario ok build "$arg" x '.#x'
    expect_rc "$n" 2 \
      && expect_no_lease "$n" \
      && pass "$n"
  done
  for arg in max-jobs builders extra-builders builders-use-substitutes store
  do
    n="conflict-option-$arg"
    run_scenario ok build --option "$arg" '' '.#x'
    expect_rc "$n" 2 \
      && expect_no_lease "$n" \
      && pass "$n"
  done
  n=benign-option
  run_scenario ok build --option sandbox false -L '.#x'
  expect_rc "$n" 0 \
    && expect_trace "$n" '--option sandbox false -L .#x' \
    && pass "$n"
}

test_nix_config_env_refused() {
  local n cfg
  for cfg in 'max-jobs = 4' 'extra-builders = ssh://x' 'Builders = x' 'store = daemon'
  do
    n="nix-config-$cfg"
    SCENARIO_ENV="NIX_CONFIG=$cfg" run_scenario ok build '.#x'
    expect_rc "$n" 2 \
      && expect_err "$n" 'NIX_CONFIG' \
      && expect_no_lease "$n" \
      && pass "$n"
  done
  n=nix-config-multiline-refused
  SCENARIO_ENV=$'NIX_CONFIG=sandbox = false\n  # comment\n  Extra-Builders=ssh://x # c' run_scenario ok build '.#x'
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  n=nix-config-benign
  SCENARIO_ENV='NIX_CONFIG=experimental-features = nix-command flakes' run_scenario ok build '.#x'
  expect_rc "$n" 0 && pass "$n"
  n=nix-config-runtime
  SCENARIO_ENV=$'NIX_CONFIG=sandbox = false\nbuild-users-group =\nexperimental-features = nix-command flakes\nsubstituters = https://cache.example.org\nrequire-sigs = true\nauto-optimise-store = false # store tuning'
  SCENARIO_ENV="$SCENARIO_ENV" run_scenario ok build '.#x'
  expect_rc "$n" 0 && pass "$n"
}

test_args_after_command_not_checked() {
  local n=args-after-command
  run_scenario ok develop '.#x' --command sh -c 'echo -j'
  expect_rc "$n" 0 \
    && expect_trace "$n" 'nix develop --max-jobs 0' \
    && pass "$n"
}

test_missing_controller() {
  local n=no-controller
  SCENARIO_ENV='RWORKER_NIX_CONTROLLER=' run_scenario ok build '.#x'
  expect_rc "$n" 2 \
    && expect_err "$n" 'no controller' \
    && expect_no_lease "$n" \
    && pass "$n"
}

test_controller_from_config() {
  local n=controller-config
  mkdir -p "$WORK/home/.config/rworker-nix"
  printf '# comment\ncontroller = my-ctl\nttl = 45m\nsystem=aarch64-linux\n' \
    > "$WORK/home/.config/rworker-nix/config"
  SCENARIO_ENV='RWORKER_NIX_CONTROLLER=' run_scenario ok build '.#x'
  rm -f "$WORK/home/.config/rworker-nix/config"
  expect_rc "$n" 0 \
    && expect_trace "$n" 'rworker up --json --ttl 45m' \
    && expect_trace "$n" 'ssh -G -- my-ctl' \
    && pass "$n"
}

test_local_conf_overrides_config() {
  local n=local-conf
  mkdir -p "$WORK/home/.config/rworker-nix"
  printf 'ttl=45m\nsystem=aarch64-linux\n' > "$WORK/home/.config/rworker-nix/config"
  printf '# private\ncontroller=priv-ctl\nttl=2h\n' > "$WORK/home/.config/rworker-nix/local.conf"
  SCENARIO_ENV='RWORKER_NIX_CONTROLLER=' run_scenario ok build '.#x'
  rm -f "$WORK/home/.config/rworker-nix/config" "$WORK/home/.config/rworker-nix/local.conf"
  expect_rc "$n" 0 \
    && expect_trace "$n" 'ssh -G -- priv-ctl' \
    && expect_trace "$n" 'rworker up --json --ttl 2h' \
    && pass "$n"
}

test_bad_inputs() {
  local n
  n=bad-subcommand
  run_scenario ok eval '.#x'
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  n=missing-subcommand
  run_scenario ok
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  n=bad-option
  run_scenario ok --bogus build
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  n=bad-ttl
  run_scenario ok --ttl '1h;reboot' build '.#x'
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  n=bad-profile
  run_scenario ok --profile '-oProxyCommand=x' build '.#x'
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  n=private-key-refused
  SCENARIO_ENV='RWORKER_NIX_KEY=/home/u/.ssh/id_ed25519' run_scenario ok build '.#x'
  expect_rc "$n" 2 && expect_err "$n" '.pub' && expect_no_lease "$n" && pass "$n"
  n=bad-controller
  SCENARIO_ENV='RWORKER_NIX_CONTROLLER=-oProxyCommand=x' run_scenario ok build '.#x'
  expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
}

test_remote_build() {
  local n=remote-build store
  store='ssh-ng://agent@100.64.0.7?ssh-key=/home/u/.ssh/id_ed25519&base64-ssh-public-host-key='
  run_scenario ok remote-build --refresh --no-link --print-out-paths \
    'github:o/cfg#termuxppConfigurations.p11.system' 'github:o/cfg#termuxppConfigurations.zf10.system'
  expect_rc "$n" 0 \
    && expect_trace "$n" 'nix flake metadata --json --refresh github:o/cfg' \
    && expect_trace "$n" 'nix flake prefetch --json --refresh github:o/cfg' \
    && expect_trace "$n" "nix copy --no-check-sigs --to $store" \
    && expect_trace "$n" '== /nix/store/src-top /nix/store/src-pub' \
    && expect_trace "$n" 'rworker-ssh-command nix build --no-link --print-out-paths github:o/cfg/locked-rev\?narHash=sha256-x#termuxppConfigurations.p11.system' \
    && expect_trace "$n" "nix copy --no-check-sigs --from $store" \
    && expect_trace "$n" ' /nix/store/aaaa-system-a /nix/store/bbbb-system-b' \
    && expect_trace "$n" 'NIX_SSHOPTS=-o StrictHostKeyChecking=yes' \
    && expect_trace "$n" 'rworker down w-test1' \
    && expect_err "$n" "skipping input 'priv'" \
    && expect_no_trace "$n" '--max-jobs 0' \
    && pass "$n"
  if [[ "$(< "$WORK/out")" != $'/nix/store/aaaa-system-a\n/nix/store/bbbb-system-b' ]]
  then
    fail "$n-stdout" "unexpected stdout: $(< "$WORK/out")"
  else
    pass "$n-stdout"
  fi
}

test_remote_build_nix_cache() {
  local n=remote-nix-cache
  : > "$WORK/creds"
  SCENARIO_ENV="RWORKER_NIX_AWS_CREDENTIALS=$WORK/creds" run_scenario ok remote-build --no-link 'github:o/cfg#x'
  expect_rc "$n" 0 \
    && expect_no_trace "$n" '--no-nix-cache' \
    && expect_trace "$n" 'RWORKER_AWS_CREDENTIALS_FILE='"$WORK/creds" \
    && pass "$n"
  n=remote-nix-cache-unreadable
  SCENARIO_ENV="RWORKER_NIX_AWS_CREDENTIALS=$WORK/missing" run_scenario ok remote-build --no-link 'github:o/cfg#x'
  expect_rc "$n" 0 \
    && expect_trace "$n" '--no-nix-cache' \
    && expect_err "$n" 'not readable' \
    && pass "$n"
  n=build-never-gets-cache
  SCENARIO_ENV="RWORKER_NIX_AWS_CREDENTIALS=$WORK/creds" run_scenario ok build '.#x'
  expect_rc "$n" 0 && expect_trace "$n" '--no-nix-cache' && pass "$n"
}

test_remote_build_failures() {
  local n scenario
  for scenario in remote-bad-output remote-no-output remote-build-fails remote-lock-fails
  do
    n="$scenario"
    run_scenario "$scenario" remote-build --no-link 'github:o/cfg#x'
    expect_rc "$n" 1 \
      && expect_no_trace "$n" 'nix copy --no-check-sigs --from' \
      && expect_trace "$n" 'rworker down w-test1' \
      && pass "$n"
  done
}

test_remote_build_refuses_bad_args() {
  local n args
  local -a cases=(
    'remote-build github:o/cfg#x'
    'remote-build --no-link'
    'remote-build --no-link github:o/cfg'
    'remote-build --no-link --impure github:o/cfg#x'
    'remote-build --no-link #x'
  )
  for args in "${cases[@]}"
  do
    n="remote-refuses '$args'"
    # shellcheck disable=SC2086 # split the case into words on purpose
    run_scenario ok $args
    expect_rc "$n" 2 && expect_no_lease "$n" && pass "$n"
  done
}

test_help() {
  local n=help
  run_scenario ok --help
  expect_rc "$n" 0 && pass "$n"
}

test_down_option() {
  local n=down-option
  run_scenario ok --down w-old
  expect_rc "$n" 0 \
    && expect_trace "$n" 'rworker down w-old' \
    && expect_no_trace "$n" 'rworker up' \
    && pass "$n"
  n=down-bad-name
  run_scenario ok --down '-x'
  expect_rc "$n" 2 && expect_no_trace "$n" 'rworker down' && pass "$n"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac

  WORK=$(mktemp -d "${TMPDIR:-/tmp}/rworker-nix-test.XXXXXX") || return 1
  trap 'rm -rf "$WORK"' EXIT
  PATH_BASE="$PATH"
  mkdir -p "$WORK/home/.ssh"
  : > "$WORK/home/.ssh/id_ed25519.pub"
  make_fakes

  SCENARIO_ENV=""
  local t
  for t in $(compgen -A function test_)
  do
    SCENARIO_ENV=""
    "$t"
  done

  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  (( FAIL == 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
