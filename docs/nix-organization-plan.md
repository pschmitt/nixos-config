# Nix organization audit — November 2026

## Scope and baseline

The repository documents clear ownership boundaries in [Architecture](architecture.md): reusable implementation belongs in modules, optional capabilities in `profiles/features/`, role composition in `profiles/specializations/`, and deliberately universal policy in `profiles/base/`. The same document warns that import relocation can reorder merged lists and generated units. The recent cleanup already removed the broken Home Manager export, consolidated initrd Wi-Fi, moved Tor/Wireshark/NRF/Waydroid into feature paths, and updated the architecture docs. Treat these as completed baseline, not audit targets.

The prior behavior comparison is the gate: 27 of 28 host derivations matched; the remaining ARM evaluation hit the known existing GHC error. The private SOPS generated-file `readFile` IFD was fixed and verified byte-for-byte. Restic import relocation was withdrawn after it changed list ordering and derivations. Preserve this evidence and ordering constraint in every follow-up.

## Findings by confidence

### Concrete cleanup candidates

1. **`modules/nixos/default.nix` is a no-op placeholder.** It contains only an example comment and is not referenced by the flake or repository imports. Confirm with a complete path/reference search before removing or repurposing it. The public `nixosModules` export set is explicit; do not infer that a file is an export merely from its directory name. Check the private input consumers before changing any actual export.
2. **`profiles/headless-browsers.nix` is an import-only wrapper.** It only imports the browser-daemon service module; current consumers are the build-node role and selected hosts. The architecture guidance discourages wrappers that add no policy or meaningful boundary. Decide whether this is a deliberate named capability used by several consumers; if not, move the import to those consumers in a separate mechanical change. First preserve each consumer’s import location/order and compare derivations.
3. **The development-shell interface was misleading.** `shell.nix` advertised standalone `nix-shell`, but required `checks` supplied only by the flake. The cleanup makes its arguments explicit and describes it as the flake development-shell definition. The separate `nixpkgs.nix` helper exists and uses lock-pinned `fetchTarball`; inventory its legacy consumers before removing this evaluation-time fetch path.

### Likely ownership drift; validate before moving

4. **`profiles/base/default.nix` imports Android USB access and AppImage support.** These are optional capabilities, while the repository says base is intentionally universal and optional capabilities belong in features. However, Android access currently has a stated headless-host ACL rationale and AppImage is platform-gated. Inventory all base consumers and actual users first; move only after confirming which hosts need these features. Keep any host-specific exception in its host or role.
5. **Base imports both Docker and Podman and selects Docker as the OCI backend.** This is a broad baseline with material runtime, firewall, daemon, and package effects. Many services rely on `virtualisation.oci-containers`, and some rely on the backend choice. Do not split Docker/Podman just to satisfy folder shape. Inventory OCI service consumers and host-specific runtime needs; consider a reusable container-runtime feature/role only if it has a stable consumer set and can preserve backend and ordering exactly.
6. **`profiles/specializations/workstation/default.nix` imports `../laptop`.** This is intentional today: the file describes interactive laptop/desktop hosts and the workstation role adds GUI/work features on top. The naming may obscure that dependency, but the import does not prove a layering bug. Consider renaming or factoring only after checking all role consumers and options supplied by the laptop role; keep it below shared features in the established ordering.

### Own flake and package interface review

Fix these concrete development-shell references before stylistic output cleanup:

- [myl-discovery](https://github.com/pschmitt/myl-discovery/blob/main/flake.nix) references `self.packages.${system}.default` in its shell hook, but exports only the named package and legacy `defaultPackage`.
- [sendmyl](https://github.com/pschmitt/sendmyl/blob/main/flake.nix) references `self.packages.${system}.myl-discovery` in shell inputs and `.myl` in its shell hook; neither is exported there. Select the intended dependency from its input and the actual application package, then evaluate and enter the shell remotely.

These are source-level defects; dependency/toolchain failures may also need resolving before the shells can be tested.

7. **Root flake inventory:** the broader read-only inventory covers 39 active non-fork GitHub root flakes plus maintained local forks. Their package-level patterns are separate audit items from host profile ownership. `flake.nix` records several of these inputs, including [jellysync](../flake.nix), [myl-discovery](../flake.nix), [poor-tools](../flake.nix), [sendmyl](../flake.nix), [tdc](../flake.nix), and [vodafone-station-cli](../flake.nix). The `docker-compose-bulk` project also belongs in the package interface audit.
8. **Legacy package outputs:** `tdc`, `docker-compose-bulk`, `myl`, `sendmyl`, `vodafone-station-cli`, and `myl-discovery` expose `defaultPackage` instead of canonical `packages.<system>.default`. Update each output in its own project change, without compatibility aliases, after checking its consumers. For `tdc`, `version = "latest"` is metadata only: `src = ./.` fixes the source to the flake revision, so do not characterize it as unreproducible.
9. **Embedded modules:** `jellysync` has a roughly 480-line Home Manager module embedded in its 583-line flake; `poor-tools` embeds a NixOS module. Extract these into focused files while preserving output names and `self`/default-package semantics. Treat each as a behavior-preserving project refactor with direct output comparisons.
10. **ISO outputs:** `iso` and `iso-multios` use identical module lists, as do `iso-private` and `iso-private-multios` ([definitions](../flake.nix)). This is redundant composition and the naming/comment relationship needs investigation. It does not establish a boot defect: upstream may support the `findiso` parameter without a distinct NixOS module list. Verify boot behavior before proposing output changes.

## Prioritized next steps

1. **Fix broken own-flake development shells first**, then **close low-risk dead-code questions:** reference-search `modules/nixos/default.nix`; inspect all consumers of `profiles/headless-browsers.nix`; inventory consumers of the legacy `nixpkgs.nix` helper. Document the decision before deleting or changing paths.
2. **Build a capability/consumer matrix:** for Android USB, AppImage, Docker, Podman, and OCI service modules, list importing hosts/roles, required options, and effects (packages, units, firewall, backend). Mark deliberate universal policy separately from optional host capability. Do not move anything based on filenames alone.
3. **Choose one mechanical change at a time:** start with confirmed no-op/wrapper cleanup, then optional baseline capabilities if the matrix supports it. Keep behavior changes out of these commits. Preserve import order where it affects merged lists; do not replace list ordering with override priorities.
4. **Verification gate for each change:** format changed Nix files with `nixfmt`; run `statix check` and `deadnix` as applicable. On an rworker, compare a clean baseline and changed tree for every affected host and installation image, inspect differing derivations with `nix-diff`, and compare relevant rendered service settings and secret source mappings. Never evaluate or build locally. Require equal derivations for a mechanical relocation; explain any intentional difference before proceeding. Recheck the ARM host separately once the existing GHC failure is resolved.
5. **Review exports and consumers before deleting modules:** public module exports are an interface to the private flake. Keep export names stable until private consumers migrate, and never add private identifiers or secrets to this public repository.

## Limits

The completed changes above were validated remotely. The remaining findings are source-level review, not a claim that every owned flake builds on every platform. The inventory covers active GitHub root flakes and maintained local checkouts; archived repositories, undiscovered nested flakes and other forges may need a separate pass. User changes were preserved. Behavior changes and fleet-wide deployment are separate from mechanical organization work.
