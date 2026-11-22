---
name: termuxpp
description: Build, debug or validate the TermuxPP Android app, its nixpp runtime, integrated API and Tasker components, or tpp command-line tools.
---

# TermuxPP development and validation

The current source of truth is the [TermuxPP repository](https://github.com/pschmitt/termuxpp), its `AGENTS.md` and `docs/en/termuxpp-differences.md`. The Android API and Tasker components are integrated into the single application under `android/components`; do not assume separate companion APKs or Debian helper packages are used. Packages, including `tpp-cli`, `tpp-api`, `tpp-session` and `nixpp`, live under `pkgs/`.

Load `rworker` before builds or substantial tests, `adb` and `brkn-infra` before device work, and `nixpp` for guest system operations. Claim the specific work and any Android device through Concord before changes or device tests.

## Builds

Follow the repository's `AGENTS.md`: run Gradle on a remote worker in its Android Nix development shell, including an APK assembly when validating Android builds. Java-only tests do not prove the APK builds. Build guest Nix packages remotely; do not build on a phone or the local workstation.

The app's Android package identity is `dev.pschmitt.termux`; Java namespaces may still use `com.termux`. Do not infer one from the other. Preserve Android authorization and data, use `adb install -r` for an authorized APK update, and never clear app data or uninstall without explicit approval.

## CLI and device validation

`tpp` dispatches the integrated API and session commands; run `tpp list`, `tpp COMMAND --help`, and `tpp --json COMMAND` to inspect the current interface. Structured responses have human-readable output by default; binary operations must remain byte-preserving. Continuous streams and plugins have their own contracts: check the command and `docs/en/termuxpp-differences.md` rather than assuming all output is one JSON document.

In the Nix guest, `tpp update` and `tpp permissions` are provided by guest plugins when installed by the corresponding Home Manager modules; they are not native API subcommands. Use `tpp-adb-shell` for ADB access. Avoid triggering updates, permission grants, or reading personal data during casual smoke tests.

Select and verify the intended device and its serial, test the actual newly built artifact rather than the installed older executable, and record separately what was built, installed, tested, and left untested. Preserve backups and remove only your own temporary files. Publish only when authorized; do not create a release or pull request unless requested.
