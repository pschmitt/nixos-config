# Nix organization audit — November 2026

## Scope and outcome

This audit covers the public and private NixOS configuration, 39 active owned
GitHub root flakes, and maintained local fork checkouts. It is a source and
organization audit; it does not claim every application works on every platform.
[Architecture](architecture.md) defines the ownership rules for future changes.

## Completed cleanup

| Finding | Resolution |
| --- | --- |
| Optional applications implemented inside the laptop role | Moved Tor, Wireshark, NRF tools and Waydroid into feature directories, keeping their consumers and import positions |
| Initrd Wi-Fi options separated from their implementation | Consolidated them into `modules/initrd-wifi.nix` |
| Broken Home Manager export | Removed the export whose implementation file did not exist |
| Capabilities implemented inside the universal baseline | Moved Android USB access, AppImage and container implementations into `profiles/features/`; base still selects the same policy |
| Headless-browser import-only wrapper | Consumers import the browser-daemon service directly |
| Unused NixOS placeholder and legacy package entrypoint | Removed `modules/nixos/default.nix` and `nixpkgs.nix`; package composition requires explicit `pkgs` and `inputs` |
| Misleading standalone development-shell entrypoint | `shell.nix` explicitly receives the flake's package set and checks |
| Duplicate MultiOS configuration outputs | Publishing uses the canonical ISO configurations; artifact names remain unchanged |
| Evaluation-time build in the private SOPS template | Assign the generated INI file directly to the template's `file`, without `builtins.readFile` |
| Inconsistent owned Home Manager output names | Public modules and jcalapi use `homeManagerModules`; the jcalapi pin and consumer migrate together |
| Legacy package output names | Replaced `defaultPackage` in the six affected application flakes with `packages.<system>.default` |
| Broken or stale Python shell wiring | Development shells inherit application dependencies and import the checkout |
| Large modules embedded in flakes | Extracted Jellysync's Home Manager module and poor-tools' NixOS module into their `nix/` directories |

No compatibility exports were added. Named package outputs used by consumers
remain alongside the default package. Third-party flake interfaces retain their
upstream names.

The six package-output migrations are
[tdc](https://github.com/pschmitt/tdc),
[docker-compose-bulk](https://github.com/pschmitt/docker-compose-bulk),
[myl](https://github.com/pschmitt/myl),
[myl-discovery](https://github.com/pschmitt/myl-discovery),
[sendmyl](https://github.com/pschmitt/sendmyl), and
[vodafone-station-cli](https://github.com/pschmitt/vodafone-station-cli).
Module extractions are in
[jellysync](https://github.com/pschmitt/jellysync/tree/main/nix) and
[poor-tools](https://github.com/pschmitt/poor-tools/tree/main/nix).

## Capability ownership and preserved policy

The baseline is shared by full server roles, the workstation role and the
full-base single-board configuration. Minimal installation and worker images
have separate compositions. Moving implementation does not narrow that existing
consumer set.

| Capability implementation | Current selection and effects |
| --- | --- |
| `profiles/features/development/android-usb.nix` | All full-baseline consumers: ADB group membership and USB rule, including headless USB hosts |
| `profiles/features/desktop/appimage.nix` | All full-baseline consumers: AppImage support is enabled only on x86_64; binfmt policy is preserved |
| `profiles/features/containers/docker.nix` | All full-baseline consumers: daemon, pruning, storage, firewall and monitoring policy; Docker remains the OCI-container backend |
| `profiles/features/containers/podman.nix` | All full-baseline consumers: Podman, pruning, compose tooling and bridge DNS firewall rules |
| `profiles/features/containers/default.nix` | Composes the two engines in their original order; this is a policy bundle, not an alias for one import |
| `services/headless-browsers/browser-daemon.nix` | Selected directly by the existing build-server role and host entrypoints |

Hardware-specific storage overrides remain in hardware profiles. Replacing the
OCI backend or removing either engine needs a separate runtime migration, not
another directory move.

The workstation role deliberately includes the laptop role: its existing
consumers need laptop hardware and power-management policy. A future desktop-only
consumer should compose the required features rather than inherit unwanted
laptop behavior. No extra role layer was added without a consumer.

## Validation and decisions

- Compare clean baseline and candidate system derivations on a remote worker,
  including images. For removed ISO aliases, compare their old derivations with
  the canonical replacement.
- Preserve merged-list order. A proposed Restic prerequisite relocation changed
  package and backup-path ordering and was withdrawn; the original composition
  boundary remains intentional.
- Compare package recipes and dependency derivations separately from source and
  output path changes. The owned-flake refactors leave dependency pins unchanged.
- Compare extracted module option defaults, disabled/enabled configurations,
  generated configuration, units, timers and package overrides.
- Verify the private generated template's bytes and permissions; verify that ISO
  publication definitions retain their targets and behavior.
- Run formatting, statix, deadnix, relevant remote evaluations/builds and CI.
  Keep large scratch artifacts out of memory-backed `/tmp`.

The mechanical pass produced identical system derivations for 27 of the original
28 configurations; the remaining ARMv6 configuration fails identically before
and after. After removing two aliases, the final tree evaluates 25 of 26
configurations. Full derivation diffs show only the intended input metadata,
agent-documentation and jcalapi source changes: builders, platforms, arguments,
output names and dependency names are unchanged. The existing ARMv6 failure
remains the sole system evaluation failure.

The extracted module comparisons pass for option defaults, disabled/enabled
states, generated Jellysync configuration and a custom package override. Package
recipe/dependency comparisons pass for the nine changed application flakes.
Linux builds pass for the six package-output migrations and jcalapi. Shell
imports and CLI smoke checks passed for the applicable migrations except the
Vodafone failure below. Module-only extractions were evaluated without
rebuilding unchanged application recipes. Application Nix lint is green;
Vodafone's separate container workflow has the unrelated failure below.

## Issues identified outside the organization changes

These were the original findings. The follow-up section below records repairs
and their validation separately.

| Issue | Evidence and suggested follow-up |
| --- | --- |
| ARMv6 system evaluation cannot bootstrap GHC | Baseline and candidate fail identically. Review the unsupported Haskell package or toolchain separately; do not silently drop software from a refactor |
| `myl` x86_64 Darwin evaluation fails | Its pinned Nixpkgs no longer supports that platform. Choose a supported Darwin toolchain or explicitly revise the platform contract |
| Vodafone CLI import fails | Baseline and candidate packages both lack `aiovodafone.models` in the pinned `aiovodafone` dependency. Align the application imports and dependency version, then test against a mock device |
| Vodafone container CI | The unchanged ARMv7 Alpine/Python image fails building `orjson` because its Rust target/toolchain is unavailable. Resolve container packaging separately; Nix lint passes |
| `tdc` package version is `latest` | This is misleading metadata, not an unpinned source: `src = ./.` remains revision-bound. Derive the version from project metadata in a separate packaging correction |

## Follow-up packaging and coverage

The follow-up separates packaging repairs from the behavior-preserving moves:

- The ARMv6 failure comes from `tcpdump` → `libpcap` → `rdma-core` →
  Pandoc's GHC bootstrap. Disabling only `rdma-core`'s optional manpages in
  that host's overlay makes all 26 system configurations evaluate. The
  runtime library and packet-capture functionality remain enabled. This is
  evaluation coverage, not an ARMv6 image build or boot test.
- `myl` tracks `nixpkgs-26.05-darwin`, the final Nixpkgs release supporting
  Intel macOS. All four default system package evaluations and the Linux
  build pass. This preserves the declared platform contract; Darwin binaries
  were not built on the Linux worker.
- `tdc` reads its package version from `pyproject.toml`. Its Linux build and
  command-help smoke test pass.
- Vodafone's Nix package uses `aiovodafone` 3.3.0, whose dependency minimums
  work with both the maintained 26.05 package set and this repository's
  Nixpkgs override. The newer Python lock remains valid for pip/uv consumers;
  it requires dependencies not yet packaged by Nixpkgs. Import, dependency
  version and mock-device checks pass without relaxing requirements. Its
  Alpine build installs the Rust toolchain needed by `orjson`
  when no ARMv7 wheel is available; an ARMv7 container build and CLI help smoke
  test pass under emulation. No live router was contacted.

Expanded discovery found one active nested flake,
[`stricknani/android`](https://github.com/pschmitt/stricknani/tree/main/android).
It exports Linux development shells and checks rather than application
packages. Both development-shell derivations evaluate; its documented Android
command-line-tools workaround remains intentional. This audit does not claim a
fresh Android application build.

A recursive tree inventory of 208 archived owned GitHub repositories found
two flakes, both at the root:
[`nix-snapd`](https://github.com/pschmitt/nix-snapd) and
[`rbw-auto`](https://github.com/pschmitt/rbw-auto). They remain archived and
were not modernized or built. The active nested-flake discovery used GitHub
code search, so unindexed files remain a coverage limitation.

Bounded checks of the configured additional forges found one owned fork with a
root flake and eight personal-namespace projects (two active, six archived),
one containing a root flake. The fork's recursive tree response was truncated,
so nested coverage there is incomplete. Private project identifiers and source
contents are deliberately omitted from this public report. Other accounts and
unconfigured forges remain outside the inventory.

The independent private flake's development shells evaluate on all four
default systems. It uses canonical package, application and shell outputs,
with pinned inputs and no evaluation-time fetches. One unused output argument
remains a minor lint cleanup; no private application was built or run.

Application/API changes and runtime migrations are separate work from the
original organization pass.
