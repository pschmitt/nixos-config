# Overlay rules

Follow the root [AGENTS.md](../AGENTS.md) for coordination, validation and
deployment. Keep the hotfix list as short as possible: every retained workaround
needs current evidence that it is still necessary.

## Placement

- `default.nix` composes overlays and exposes package sets. Keep package-specific
  workaround bodies out of it.
- Put temporary upstream or Nixpkgs fixes in `hotfixes/<package>.nix`, with a
  short, explicit import list in `hotfixes/default.nix`. Do not auto-import every
  file in the directory or retain compatibility aliases for moved files.
- Keep the export shape explicit: package attribute overrides and Python
  extensions have separate composition points in the hotfix registry. An
  ordered patch bundle may instead be imported by its owning package overlay
  when this preserves patch order; note that exception in the registry.
- Put deliberate, lasting package customizations in `<package>.nix`. A temporary
  version pin, missing dependency, build repair or test workaround is a hotfix,
  even if it has been around for a long time.
- New package definitions belong in `../pkgs/`; service configuration and host
  policy belong in modules, profiles or hosts, not overlays.
- Keep non-trivial patches in patch files beside the owning hotfix, or in a
  clearly named package subdirectory. Remove unused patches with their fix.

## Writing overlays

- Use `prev.<package>` as the base of an override and `final` for dependencies
  that should see the composed package set. Avoid self-reference through
  `final.<package>` when defining that same package.
- Use `override` for derivation arguments, `overrideAttrs` for derivation
  attributes, and `overrideScope` or package-set extensions for scoped packages.
- Preserve existing patches, hooks, dependencies and extensions unless replacing
  them is intentional and explained. Compose overlays explicitly; shallow `//`
  merges must not silently discard another overlay's Python extensions or
  nested package overrides.
- Apply a fix to the package set that actually consumes it. Check alternate
  Nixpkgs inputs and Python scopes; do not assume a top-level override reaches
  all consumers. Explain any necessary application to more than one package set.
- Prefer a small upstream patch to broad rewrites or disabled checks. If a test
  must be disabled, name the exact test and explain the failure. Disabling an
  entire test suite or metadata checks requires specific evidence and a removal
  condition. Never relax dependency requirements just to make a build pass.

## Hotfix lifecycle

Each hotfix must record concise comments containing:

- The observed failure and affected package/platform or interpreter.
- An upstream issue, pull request or commit link when available; otherwise state
  that the fix is local and explain why.
- A concrete removal condition, such as an upstream commit reaching our pin.
- The last review date, exact relevant Nixpkgs revision and validation result.

Review all hotfixes whenever a relevant Nixpkgs input is updated and at least
monthly. Review a package's fixes when updating that package too. A review means
checking the pinned package source and upstream status, then testing removal
where warranted; merely updating a date is not a review. Record retained fixes'
evidence in their files and summarize removals or unresolved failures in the
commit or audit notes. An overdue review calls for investigation, not automatic
expiry of a fix that may still be required.

Prefer deleting a workaround once the pinned package includes the fix. A new
upstream release alone is insufficient: verify that our selected package uses
it and no longer needs the patch. Reassess development-version pins, master
package substitutions and test exclusions especially carefully. Do not move an
obsolete fix into a permanent overlay merely to shorten the hotfix list.

## Validation

Separate mechanical moves from package upgrades and removals. Compare affected
derivations before and after a reorganization, preserving overlay ordering and
all consumers. For a removal, build the unmodified package on the remote worker,
run relevant checks and safe smoke tests, and verify dependent configurations.
Do not perform live service mutations as a smoke test. Follow the root rules for
formatting, linting, broader configuration comparisons and deployment.

Evaluating a `drvPath` is not a build. When testing a derivation file directly,
use `nix-store --realise /nix/store/...drv` or an explicit output selector with
`nix build '/nix/store/...drv^*'`; a bare `.drv` path can succeed without building
its outputs. Verify the resulting output paths before reporting build success.
