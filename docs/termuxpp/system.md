# Declarative guest system

This experimental system layer sits beneath Home Manager on the droid-nix
runtime. It does not replace Android, run systemd, or claim NixOS compatibility.
Assembly, candidate preparation and the management protocol have worker tests.
Coordinated system/Home Manager activation has also passed on both Android
profiles, including configured-editor and thorough runtime acceptance. This is
not a claim of NixOS compatibility or qualification of every Android lifecycle.

## Interface

`termuxppConfigurations.<host>.system` builds a closure containing:

- `sw`: independently selected guest-system packages and `nixpp`;
- `etc`: declarative system files with safe relative paths;
- `home-manager`: the matching HM generation;
- `manifest.json`: versioned identity, runtime, session and child HM metadata.

An associated HM generation enables `activationSupported`; a system without HM
can be assembled and prepared but cannot use coordinated activation. Existing
`homeConfigurations` outputs remain available during migration. Core packages
currently overlap between the two layers; activation selects system configuration
and packages together with the associated HM generation.

Build full closures on a disposable worker and publish them directly to the
cache. Never compile them on the workstation or phone:

```sh
nix build '.#termuxppConfigurations.zf10.system'
nix build '.#termuxppConfigurations.p11.system'
```

## Guest command: nixpp

The user-facing interface is **`nixpp`**, a Rust executable built for the Linux
guest and Android/Bionic from the same source, maintained in the
[termuxpp repository](https://github.com/pschmitt/termuxpp/tree/main/nix/nixpp) and
taken from its flake input (`inputs.termuxpp.lib.nixpp.packagesFor pkgs`). The guest
client and native controller no longer require a Python interpreter. The native
executable runs independently of the guest so broken guest activation cannot
disable recovery.

Human-readable output uses restrained terminal colors; redirected output and
`NO_COLOR` disable automatic styling. Use `--json` for machine-readable results.
Nix, Home Manager activation and the launcher (built from pinned droid-nix
sources) remain upstream tools, not reimplementations inside the manager.

```sh
# In the guest, with the matching native controller running:
nixpp status
nixpp doctor
nixpp list-generations
nixpp check HASH-termuxpp-system-HOST
nixpp switch HASH-termuxpp-system-HOST
nixpp rollback
nixpp recover

# Check or install the system CI published for this guest in the signed cache:
nixpp upgrade --dry-run
nixpp upgrade

# Evaluate and build the flake configured in /etc/nixpp/upgrade.json instead:
nixpp upgrade --build --dry-run
nixpp upgrade --build

# Build or rebuild an explicit target using configured remote builders:
nixpp build --flake /path/to/config --host HOST
nixpp rebuild --flake /path/to/config --host HOST
# Alternatively lease a worker through rworker-nix to build there:
nixpp rebuild --flake /path/to/config --host HOST --rworker
# ... and evaluate there too (only the flake is locked and shipped from here):
nixpp rebuild --flake /path/to/config --host HOST --remote-eval
```

`status` shows the active and previous systems. Use `status --all` or
`generations` to list all retained systems. `doctor` checks the native
controller, the local Nix store, configured SSH builders and the signed cache
pin. `fetch latest` runs the configured upgrade.

`upgrade --build` selects the host and flake from the system configuration. It
accepts `--flake` and `--host` overrides, `--rworker` to build on the
disposable worker and `--remote-eval` to evaluate there too; each of them
implies `--build`. With `--build`, `--dry-run`
runs Nix's build planner without contacting the native controller.

Plain `upgrade` (formerly `--from-cache`, still accepted) reads the host's published pin, verifies the system
against the configured cache signing keys, and copies its closure. It uses
the read-only cache credentials rendered by SOPS. It does not fetch or
evaluate the flake and does not require SSH to a builder. Ordinary Nix
commands also use this S3 cache as a substituter. They use the rendered
read-only cache credentials when `AWS_SHARED_CREDENTIALS_FILE` is unset.

`build` returns a store path. `rebuild` builds, prepares a candidate if needed,
then requests a coordinated switch. `--max-jobs 0` prevents phone-side compilation
when using normal builders; `--rworker` uses the existing wrapper which enforces
the same policy. The guest reads its configured remote builders from
`/etc/nix/machines`. The chosen remote builder must already be trusted.
This is a guest-system rebuild, not `nixos-rebuild` or Android OS management.

`NIXPP_RUNTIME` supplies the native runtime directory through `/android`;
`NIXPP_SOCKET` supplies the guest-visible management socket. The launcher sets
both. `rebuild --runtime PATH` can override the former. The native service runs
outside the guest, permits only same-UID clients and fixed management operations,
and executes no arbitrary client-supplied native command.

Guest services are declared with `services.<name>.command` in a TermuxPP system
configuration. Enabled services start when a guest session opens. The `svc`
command lists their state, starts, stops or restarts one service, and returns
its most recent 200 log lines with `svc logs NAME`. Service processes run under
the guest user and are supervised with runit.

`services.<name>.allowedSsids` restricts a service to exact Wi-Fi names. The
TermuxPP app writes the connected network to `network.json` in the runtime
directory (`/run/nixpp-runtime/network.json` in the guest) on every change and
at least once a minute. Android reveals the name in the background only with
location access "Allow all the time"; `termuxpp-setup-permissions grant` sets it.
The guest supervisor starts the service on an allowed network and stops it
elsewhere. With no Wi-Fi, a withheld name or state older than five minutes it
stays down, and `svc list` shows that it is waiting for an allowed network.
`svc start` refuses to start it elsewhere; a manual `svc stop` is kept.
TermuxPP's settings (Nix guest services) change a service at run time
through `service-state/settings.json`, whose keys replace the configured
values: `enabled` (start on boot), `wifiRestricted` (stop outside the
allowed networks and restart it once back; services that are off or were
stopped by hand stay off) and `allowedSsids`. Start on boot and the Wi-Fi
restriction are independent. `svc show SERVICE` (or `svc --json show`) lists
the state, PID, uptime, listening ports, command and where each setting
comes from; `svc --json list` reports the same for every service. The ADB
shell listener belongs to the app and uses `fullNix.adbShell.allowedSsids`
instead.

Wi-Fi names identify places, so keep them in SOPS: `allowedSsidsFile` (and
`fullNix.adbShell.allowedSsidsFile`) read one name per line from a secret at
run time instead, so the names never reach the Nix store. An unreadable file
allows no network for a service; the ADB property is then left unchanged. A
host sets the system-layer option in `hosts/<host>/system.nix` and the Home
Manager one in `hosts/<host>/home.nix`; p11 restricts sshd and the ADB shell to
the `wifi/home-ssids` secret. Test the
gating with real runit:

```sh
nix shell nixpkgs#jq nixpkgs#runit nixpkgs#util-linux \
  -c bash modules/nixpp/scripts/test-svc-network.sh
```

## Candidate preparation

```sh
/nix/store/HASH-termuxpp-system-HOST/sw/bin/nixpp prepare \
  --runtime /android/ABSOLUTE_NATIVE_RUNTIME_DIRECTORY \
  /nix/store/HASH-termuxpp-system-HOST
```

Preparation validates schema, runtime ABI, identity and required session paths,
then materializes a private `/etc` snapshot and six-line data descriptor under
`system-candidates/HASH-termuxpp-system-HOST/`. Declared files overlay runtime
defaults. Android-owned `passwd` and `group` cannot be overridden; symlinked
directories and special files are rejected. Generated files link to the guest
store. nixpp copies `termuxpp-release` because the native launcher reads it
before mounting the store. The snapshot also carries the Android-provided
defaults. A direct GC root retains the system closure and its matching HM
generation. Candidates
are never overwritten, and failed copies are not published.

Explicit `session.sh --system CANDIDATE -- COMMAND` uses that candidate without
selecting it or activating HM. Sessions share the persistent home and store;
they are not disposable homes or a security sandbox. Acceptance uses isolated
fixtures, not real vault authentication or cloud operations.

## Activation and recovery

The matching native TermuxPP controller serializes mutations with a lock:

1. Validate the retained candidate and run thorough isolated acceptance in a
   fresh session using its `/etc` and system package path.
2. Persist a journal recording the old and proposed system/HM pair.
3. Activate the associated HM generation in that fresh candidate environment.
   Its existing activation hooks include preflight and active acceptance.
4. Repeat candidate acceptance and atomically publish default system selection
   and generation state. Remove the journal only after publication succeeds.

First migration requires a verified old HM generation, passed to the native
`nixpp --runtime DIR controller switch CANDIDATE --previous-home-manager STORE_PATH`.
A direct GC root retains
that baseline. Subsequent guest `nixpp switch` operations use recorded state.

Activation cannot make arbitrary HM file changes atomic. Failure or interruption
after journaling leaves the operation pending and blocks another switch.
`nixpp recover` explicitly reactivates the journal's old HM generation in its
old system environment and restores selection. Failed recovery retains the
journal. If the guest cannot start, invoke the native controller from recovery.

`rollback` activates the retained previous pair, including the original HM-only
baseline after the first migration. Prepared system GC roots retain matching
closures; this implementation does not garbage-collect candidates or backups.
New default sessions follow `current-system`. Existing sessions keep their
selected generation. In each managed session, `/run/current-system/sw/bin`
contains that generation's system tools. The launcher and guest SSH server add
this directory to `PATH`.

The following device results cover the earlier Python controller, not acceptance
of the Rust replacement. The second profile's migration exercised a controlled
pre-activation interruption and recovery. Its original HM-only baseline rollback then failed during active
acceptance on that baseline's known JIT-enabled Neovim startup fault, after HM
had changed files. Recovery restored the corrected system/HM generation and
passed acceptance; the old baseline was not retried until it happened to pass.
The original baseline remains retained, but is not a qualified editor fallback.
Native recovery is independent of that old HM generation. A subsequent controlled
interruption deliberately moved the upstream HM profile to the baseline while
retaining the journal. Recovery automatically reconciled the profile with the
restored generation using upstream `nix-env --set`; fresh-session profile/state
consistency and thorough active acceptance passed. Both native controllers were
reloaded with this correction. App UI relaunch and arbitrary Android background
lifetime are not covered by these shell tests.

`--legacy` ignores selection and uses original runtime configuration, while
`--bootstrap` always retains independent native bootstrap recovery. A NixOS
`system` profile is deliberately not fabricated.

On an enrolled runtime, TermuxPP publishes its installed Android library path
at app startup and after package replacement. The native controller finishes its
current request, releases the socket, and restarts with libraries from the
installed APK. APK recovery requires the matching native nixpp and TermuxPP
app. For the first rollout to an existing installation, replace both the prefix
and staged runtime nixpp binaries, refresh the launch scripts with a native
nixpp login, and restart the legacy controller once.

When activation publishes a new generation, the service supervisor stops the
old services and starts them using the selected generation. Explicitly stopped
services stay stopped. Ordinary terminal sessions continue in the generation
they entered. Keep a separate terminal open for recovery before testing
SSH service handoff.

## Secrets (sops-nix)

Both layers can install secrets with the pinned upstream
[sops-nix](https://github.com/Mic92/sops-nix) installer; there is no systemd, no
root and no daemon. The system layer (`system/sops.nix`) reuses the pinned upstream
Home Manager module for every `sops.*` option (including templates), its assertions,
its manifest and its installer script. It is evaluated against inert option sinks
for the few Home Manager and systemd options that module writes; nothing reads
them and no systemd is run or faked. The installer script is read from the unit's
`ExecStart`, and `sops.environment` is applied from its literal values. Home
Manager keeps its own `sops.*` (see `README.md`).

**Contract with the runtime.** The manifest gains an optional field

```json
"systemSecrets": "/nix/store/<hash>-activate-secrets/bin/activate-secrets"
```

and the toplevel exposes the same executable as `bin/activate-secrets` (a symlink).
It is present only when `sops.secrets` is not empty, and absent otherwise and in
older generations. The controller runs it with no arguments in the freshly selected
candidate environment, after the journal is persisted and before the matching Home
Manager `activate`, for switch, rollback and recover. A non-zero exit fails the
activation, so no Home Manager mutation happens after a failed system secret
install. It uses `$XDG_RUNTIME_DIR` when set and falls back to
`fullNix.sops.runtimeDir` (`/run`). It is idempotent
and re-runnable for recovery.

**Separate namespaces.** The system layer uses `/run/secrets`
(link) and `/run/secrets.d` (generations); Home Manager uses
`~/.config/sops-nix/secrets` and `/run/user/<uid>/secrets.d`. Both run as the same Android UID,
so this is organization, not a security boundary: file modes are the only access
control.

**Stale secrets and baseline.** Cleanup is upstream's and there is no state of ours.
A secret dropped from a still-configured set disappears with the pruned generation
(`keepGenerations`); its custom `path` symlink dangles. Removing every secret
leaves no hook, so nothing runs and the previously installed data stays until
removed by hand; the same holds for rolling back to a generation without
`systemSecrets` (for example the original HM-only baseline). A changed
`runtimeDir` is a different location and the earlier one is not touched. Revocation
is therefore not guaranteed by activation.

**Limits.** Decrypted secrets live under `$XDG_RUNTIME_DIR`, which is `/tmp/run`:
persistent app storage in the guest, not tmpfs. They are not in the Nix store, but
they do survive reboots until removed. `sops.environment` values are literal strings
(not pre-quoted as for systemd units). `home.nix` imports `sops.nix`, which adds
nothing to a guest without secrets.

Tests: `profiles/specializations/termuxpp/sops-tests.nix` (ephemeral age key and synthetic sops file generated
inside the build) covers install, modes, templates in both layers, namespace
separation, the `%r` fallback, the exact `systemSecrets` hook in the built manifest,
failure propagation (wrong or missing key keeps what is installed), a removed
secret, the retained data when every secret is removed, upstream's assertions and no
systemd; it also evaluates the real `zf10` and `p11` configurations. Run it on a
worker:

```sh
nix build --impure --no-link -L --expr \
  'import ./profiles/specializations/termuxpp/sops-tests.nix { inputs = (builtins.getFlake (toString ./.)).inputs; }'
```

## Upstream assessment

Reviewed nix-on-droid at revision
[`3264519d7df25f82e716e83607acf5e61f89b1ea`](https://github.com/nix-community/nix-on-droid/tree/3264519d7df25f82e716e83607acf5e61f89b1ea/modules).
Its Nix module evaluation, separate system path, declarative `/etc`, generation
profile and child HM activation are the relevant architectural model. Its
[`build/activation.nix`](https://github.com/nix-community/nix-on-droid/blob/3264519d7df25f82e716e83607acf5e61f89b1ea/modules/build/activation.nix)
builder directly includes proot-static and runtime-specific login programs.
Those cannot be imported unchanged into the droid-nix launcher integration.
This implementation uses Nixpkgs `lib.evalModules` and the existing public HM
API; it does not vendor upstream implementation or add a second guest runtime.
