---
name: termuxpp
description: Build, package, debug or validate the TermuxPP fork, its AArch64 nixpp bootstrap, API/Tasker companions, TermuxAm and native API helpers.
---

# TermuxPP development and validation

Use this for TermuxPP application and companion development. For managed nixpp
profiles, yadm initialization, upgrades or recovery, use `termux-init` instead.
Load `adb` before device work and `rworker` before Android/native builds. Read
each repository's applicable instructions and claim the scope through Concord.

## Sources of truth

All forks use `main`:

- [Core](https://github.com/pschmitt/termux-app): `docs/en/aarch64-bootstrap.md`,
  `scripts/build-aarch64-bootstrap.py`, `scripts/package-helpers.py`.
- [API app](https://github.com/pschmitt/termux-api).
- [Tasker app](https://github.com/pschmitt/termux-tasker).
- [Native API tools](https://github.com/pschmitt/termux-api-package).
- [TermuxAm](https://github.com/pschmitt/TermuxAm).

Read each fork's `TERMUXPP.md` before building or installing it. Clone companions
recursively: their `termux-app` submodules pin the core's shared Gradle projects.
Publish core changes first, update the companion pins, then validate those actual
pins rather than relying on manually copied shared sources.

## Identities and signing

- Core Android ID: `dev.pschmitt.termux`; Java remains `com.termux` and
  `com.termux.shared`. Core services are `com.termux.app.TermuxService` and
  `com.termux.app.RunCommandService`. Do not derive Java class names from the
  Android application ID. Actions, permissions, extras and private paths do use
  the fork identity.
- API Android ID and Java namespace: `dev.pschmitt.termux.api`.
- Tasker Android ID and Java namespace: `dev.pschmitt.termux.tasker`.
- Companion shared UID is `dev.pschmitt.termux`; all installed apps must have
  the same signing certificate. The checked-in development key is public and
  untrusted, not a production credential.
- Keep Locale/Tasker protocol strings unchanged. Preserve same-UID, signature,
  command-permission and external-execution policy checks.
- TermuxAm's command-loaded APK keeps Java namespace `com.termux.termuxam`, but
  its caller identity must be `dev.pschmitt.termux`. Filesystem redirection
  cannot fix stock TermuxAm's `com.termux` caller identity.
- Native API tools must target the fork receiver, socket and prefix. Stock
  `termux-api` tools are not interchangeable with these helpers.

## Builds and packages

Run Gradle and Android NDK/CMake compilation on a disposable remote worker.
Read the current Gradle properties for tool versions; use Nix's wrapped aapt2
via `-Pandroid.aapt2FromMavenOverride=...` when building in a Nix SDK shell.

Use the core guide's commands rather than duplicating versioned build recipes.
Build TermuxAm's release helper APK and stage the native API install, then run
`scripts/package-helpers.py` to generate the two debs.

- The helper APK is loaded by `app_process`, not installed with `adb install`.
- Device-mode debs use `/data/data/dev.pschmitt.termux/files/usr`.
- `--bootstrap` debs use upstream archive paths for installer rewriting.
  **Never install bootstrap-mode debs directly on a device.**
- Preserve the launcher's Android 14+ read-only-dex handling. Package the helper
  APK writable by its owner (0600); the launcher makes it read-only before
  loading. Packaging it as 0400 caused dpkg `.dpkg-new` extraction to fail.
- Keep names `termux-am` and `termux-api` so nixpp's APT requirements match.
  After device installation, run `apt-mark hold termux-am termux-api` and verify
  with `apt-mark showhold`. Bootstrap builds need both corresponding
  `--hold-package` options. Version preference rules were not reliable in the
  device tests; do not substitute unverified pins for holds.

## Bootstrap

The custom AArch64 bootstrap is opt-in. Supply both
`TERMUX_BOOTSTRAP_AARCH64_ZIP` and `TERMUX_BOOTSTRAP_AARCH64_SHA256` to Gradle;
without them builds retain upstream archives. Other ABIs remain independent.

- Use a verified upstream base, a retained dependency lock/debs, the real
  Android/Bionic AArch64 nixpp binary, OpenSSH and fork-compatible helpers.
  Do not use Linux/glibc outputs or a synthetic test binary.
- `fetch` requires `--base-zip`; custom `build --base-zip` inputs also need
  `--base-sha256`. Inspect current `--help` for complete arguments.
- Run builder tests with `python -I -m unittest discover -s scripts -p 'test_*.py'`.
  Set `TERMUX_TEST_BASE_ZIP` to include the real upstream archive test.
- Run `verify ARCHIVE`, retain its checksum, and build the APK using that archive.
- Maintainer scripts are preserved but not executed. Generate SSH host keys on
  the device when needed; never embed private keys, credentials or an enabled
  SSH daemon. The fetcher does not verify repository GPG signatures; retain and
  review the lock and input hashes.
- Archive verification and a successful APK build do not prove first-run
  extraction. Do not clear an existing app's data merely to obtain this test.

## Device acceptance

Select an authorized device explicitly by serial and confirm model/product.
Resolve device roles through `brkn-infra`; never hardcode a device serial here.
Inspect existing state, back up files before helper replacement, and use
`adb install -r` without resetting data. Existing Tasker profiles must reselect
TermuxPP; do not silently rewrite them.

Test the final artifacts, not stale APKs left under older output filenames:

1. Confirm the installed core and companion actually launch. Accepted `am start`
   input alone is not proof: stale API APKs can lack their relocated application
   class. Rebuild current sources and inspect a bounded crash log if needed.
2. Install device-mode helper debs, apply and verify holds.
3. Run `termux-battery-status`, then force-stop only the fork API app and repeat
   to cover cold-start broadcast fallback. Run a harmless toast. Do not access
   clipboard, contacts, location or other personal data as a casual smoke test.
4. Build/install Tasker's instrumentation APK and run `ExecutionIntegrationTest`
   through `androidx.test.runner.AndroidJUnitRunner`. It verifies real ordered
   plug-in execution, stdout, stderr and exit status 7 without changing saved
   profiles. Command parameters belong to the nested Locale bundle; reading
   them from the top-level host intent breaks execution.
5. Run the exact bootstrap nixpp binary with `--version` on the device. This
   does not prove a configured profile, successful upgrade or yadm completion;
   use `termux-init` for those checks.

`run-as` does not inherit the normal Termux shell environment. If it is needed,
use a short-lived private launcher with HOME, PREFIX, PATH and LD_LIBRARY_PATH.
For fork prefix redirection, set `TERMUX_APP__DATA_DIR` and preload the installed
`libtermux-pkg-redirect.so`; `libtermux-exec.so` alone is insufficient. Derive the
current native library path from `pm path`, since app upgrades change it.
Termux startup may clear `$PREFIX/tmp`: a non-secret test launcher that must
survive a relaunch can live in a uniquely named private home-cache directory.
Use restrictive permissions and remove your own files afterward. Never dump
private configuration or weaken authorization to make a test pass.

## Finish

Run core shared unit tests, companion unit tests and lint, native helper builds,
Python tests and device acceptance appropriate to the change. Record separately
what was built, installed, device-tested, CI-tested and left untested. Preserve
recovery backups until migration is verified. Publish requested changes on main,
keep companion pins current, use `git-commit` and `ci-watch`, and remove temporary
files/credentials and dispose of the worker. Do not create a release or PR unless
requested.
