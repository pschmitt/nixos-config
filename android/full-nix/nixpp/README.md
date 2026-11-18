# nixpp

Rust system management for a declarative Linux guest hosted by TermuxPP.
One codebase builds two executables: Linux/glibc for the everyday guest CLI and
Android/Bionic for bootstrap, the native controller and independent recovery.
They are not interchangeable ABI builds.

Nix builds the closures, Home Manager performs its upstream activation, and
droid-nix launches the guest. nixpp coordinates those tools; it does not emulate
NixOS, systemd or a NixOS system profile. The native substrate remains available
when the selected guest generation cannot start.

## Guest commands

```sh
nixpp list-generations
nixpp build --flake path:/config --host example
nixpp rebuild --flake path:/config --host example
nixpp prepare /nix/store/STOREHASH-termuxpp-system-example
nixpp check STOREHASH-termuxpp-system-example
nixpp switch STOREHASH-termuxpp-system-example
nixpp rollback
nixpp recover
```

Builds disable local compilation. Add `--rworker` to opt into the existing worker
integration. Prepared candidates are not selected or activated until `switch`.
Activation journals the previous system/Home Manager pair and publishes selection
only after the activation and checks succeed. A retained failure journal blocks
another switch until explicit recovery.

The guest uses `NIXPP_SOCKET` (default `/tmp/nixpp.sock`). `--json` produces
machine-readable results without terminal escapes. Human output uses restrained
colors on terminals; redirected output and `NO_COLOR` are plain. `--color` selects
`auto`, `always` or `never`; `--quiet` suppresses progress and success messages.

## Native setup and recovery

Stage the Android build as `nixpp` beside the launcher, bootstrap seed and runtime
manifest. The executable contains the managed shell resources; it does not embed
the Linux package closure, the seed or the launcher binary.

```sh
./nixpp init --runtime /path/to/runtime --bootstrap /path/to/bootstrap-aarch64.zip \
  --manifest /path/to/manifest.json --certificate /path/to/cert.pem --user guest
./nixpp init --runtime /path/to/runtime --resume
./nixpp --runtime /path/to/runtime serve --socket /private/tmp/nixpp.sock
./nixpp --runtime /path/to/runtime controller list-generations
./nixpp --runtime /path/to/runtime controller recover
./nixpp --runtime /path/to/runtime controller rollback
```

A provisioning-first TermuxPP bootstrap installs `bin/nixpp` plus
`share/nixpp/{launcher,bootstrap-aarch64.zip,manifest.json}`. With those
trusted inputs bundled, run `nixpp init --user guest` from the native shell.
Init defaults to `$HOME/.local/share/termuxpp-nix`, finds assets relative to
the executable's native prefix, and uses `etc/tls/cert.pem`. `--bootstrap-dir`
overrides only the bundled-assets directory. Explicit input paths above remain
supported. Init downloads nothing besides the pinned packages from
cache.nixos.org. An interrupted package import uses `nixpp init --resume`, not
fresh extraction.

We build the launcher and seed ourselves
([`bootstrap-seed.nix`](../bootstrap-seed.nix), package
`nixpp-runtime-termux-seed`) from the pinned droid-nix sources (MIT): a static
musl `launcher` and a registered chroot store with static `nix`,
`busybox`, and the glibc `nixpp` closure. The same package carries
`manifest.json` ([`session-manifest.nix`](../session-manifest.nix)), which puts
guest `nixpp` on the first session's PATH. Init uses the bundled closure and
fetches missing session packages from cache.nixos.org. The seed is reproducible.

From a native session, `nixpp enter` opens the Nix guest. Use `--` to run a
command directly, without shell evaluation:

```sh
nixpp enter -- printf '%s\n' 'two words'
nixpp enter --outer
nixpp enter --outer -- ls -al
```

Inside a regular interactive guest, `--outer` runs in the native TermuxPP
environment through the terminal session's native parent. Exit an outer shell
to return to the guest. The handoff accepts only requests from that terminal's
foreground job, with all three streams attached to the terminal. It is separate
from the system-management socket. A guest entered through a recovery script
without a native parent can use the app's failsafe session instead.

For personal device enrollment, close other terminal sessions and open a
TermuxPP failsafe session. Run `"$PREFIX/bin/nixpp" native-shell` to load the
native prefix environment, then run:

```sh
nixpp bootstrap --host PHONE --user USER --flake FLAKE --credentials PRIVATE_DIR
```

The private directory contains `id_ed25519`, `id_ed25519.pub`, `ssh_config`,
`known_hosts`, `nix.conf`, `rbw_config` and optionally `age_key`. The Nix
configuration must name a remote builder and provide read access to the
flake's private inputs. SSH host keys must already be pinned in `known_hosts`.
The age identity, when supplied, is installed as `~/.config/sops/age/keys.txt`
for profiles that declare SOPS secrets. Credential files stay in the guest's
private home.

Enrollment sets up the requested user beside the current guest. It builds
the selected system with Nix and phone compilation disabled, activates the
initial Home Manager generation, then switches through the native controller.
The previous guest is retained at the runtime path with a `.before-enrollment`
suffix. Open a new TermuxPP session after enrollment to enter the managed
guest. Retry the same command to continue an interrupted enrollment.

The launcher carries
[`launcher-foreign-trap.patch`](../launcher-foreign-trap.patch). Android 15's
app seccomp filter traps `openat2`. Upstream's SIGSYS handler translated and
reissued its own reissued syscall again until the stack overflowed, so the
first `nix copy` of a fresh runtime died with SIGSEGV or SIGSYS inside the app.
It did not fail under `adb run-as`, which has no app filter. A trap raised by the
launcher's exempt stub now fails with `ENOSYS`, and Nix falls back to `openat`.
Test init inside the TermuxPP app, not only through `run-as`. The
`nixpp-runtime-termux` build compiles in the seed's SHA-256, and init refuses
any other seed. A nixpp built without the Nix package has no pinned seed and
refuses to prepare a runtime.

This initializes the base runtime only: it does not activate a host system,
fabricate a Home Manager baseline, replace the native shell or enable guest
login. System activation still uses the journaled controller and its gates.
No vault, SSH keys, cache credentials or private configuration are embedded.

Run native commands outside the guest. The socket requires an owned directory
that is not writable by other users, and accepts only clients with the same UID.
Direct controller operations use the same mutation locks as the service and do
not need a working socket. Do not run the former Python service concurrently.

The legacy [native bundle manager](../../nixpp) remains for unmigrated bootstrap
and recovery consumers only. It does not manage this guest system. The optional
Android API bridge is separate from this system-management port; arbitrary native
commands and a general Termux package bridge are not exposed by the controller.

## Validation

All compilation and test suites run on a remote worker:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features
cargo test --all-features
python3 -I ../system/test_nixpp_cli.py /path/to/compiled/nixpp
```

The Nix package outputs are `nixpp`, `nixpp-runtime-termux` and
`nixpp-runtime-termux-seed`. The system assembly
test also exercises the packaged CLI. See [the parity contract](PARITY.md) for the
preserved state, protocol and recovery guarantees and cut-over criteria. A
successful host build alone does not qualify Android activation or recovery.
