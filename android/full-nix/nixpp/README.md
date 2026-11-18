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

Stage the Android build as `nixpp` beside the pinned droid-nix launcher and runtime
manifest. The executable contains the managed shell resources; it does not embed
the Linux package closure or the launcher binary.

```sh
./nixpp init --runtime /path/to/runtime --apk /path/to/bootstrap.apk \
  --manifest /path/to/manifest.json --certificate /path/to/cert.pem --user guest
./nixpp init --runtime /path/to/runtime --resume
./nixpp --runtime /path/to/runtime serve --socket /private/tmp/nixpp.sock
./nixpp --runtime /path/to/runtime controller list-generations
./nixpp --runtime /path/to/runtime controller recover
./nixpp --runtime /path/to/runtime controller rollback
```

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

The Nix package outputs are `nixpp` and `nixpp-runtime-termux`. The system assembly
test also exercises the packaged CLI. See [the parity contract](PARITY.md) for the
preserved state, protocol and recovery guarantees and cut-over criteria. A
successful host build alone does not qualify Android activation or recovery.
