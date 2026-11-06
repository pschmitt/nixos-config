# Overlay review

Review date: 2026-11-06. The top-level Nixpkgs input resolves through
`flake.lock` → `nodes[root].inputs.nixpkgs` → `nixpkgs_6`, at revision
`1d060086d60cb76a40cf37109f979d88a5bd6396`.

## Correction to the initial audit

The initial removal audit mistakenly used the lock node named `nixpkgs`
(`b1b875982b17dabde9b4a37f3e229e74913e6db3`), which belongs to a nested input.
Its successful package builds did not justify removing this configuration's
workarounds. Those removal conclusions are withdrawn. All ten workarounds and
the prior hass-cli development source/patches have been restored in the new
per-package layout. No fleet activation was performed for that removal commit.

Restored fixes cover Audacity, Squeekboard, pipx, python-aodhclient, diff-cover,
websockify, torchcodec, rxvt-unicode, shadowsocks-libev and Perl DBD::CSV.
Hass-cli's upstream 1.0.0 release remains an upgrade candidate; the top-level
input does not already provide the package that the initial audit tested.

## Organization and review policy

Temporary fixes live in `overlays/hotfixes/<package>.nix`, composed explicitly
by `overlays/hotfixes/default.nix`. Noctalia's four temporary image, keyboard and
capture fixes are a patch bundle inserted at their original positions by its
own overlay. Plugin API, caffeine, OSD and notification features remain in
`overlays/noctalia.nix`. All 19 Noctalia patches still apply to the pinned source;
the split preserves their names, order and contents.

Deliberate package integrations remain in `overlays/<package>.nix`: rbw's
upstream overlay, Lan Mouse keymap/input handling, pytr's system-browser
selection, go-task's executable/completion rename, WireGuard's `wg-json`, and
the chosen zsh-completions source. The pytr patch is a separate patch file
instead of a large embedded Python replacement script.

The maintenance rules live in [overlays/AGENTS.md](../overlays/AGENTS.md).
Review fixes on every relevant input update and at least monthly (next review
by 2026-12-06). Resolve the actual input graph before testing removals. Prefer
removal only after a failing reproducer or build passes without the workaround
under the package set used by its consumers. A passing evaluation alone is
insufficient, and a warm store must not conceal evaluation-time builds.

## Validation scope

The initial reorganization's 26 NixOS evaluations and 14 retained-derivation
comparisons used the actual flake inputs and remain valid evidence for those
mechanical moves. The standalone build and test results against the nested
Nixpkgs revision are not evidence for pruning top-level hotfixes.

The corrective restoration matches all 25 compared package derivations from
the pre-reorganization overlay set under the actual top-level input.

The Termux check exposed evaluation-time reads of generated Home Manager files
and the Neovim plugin tree. These are being corrected and verified separately
with import-from-derivation disabled. Fresh-store checking also exposed a
browser-daemon Cargo-lock packaging issue; neither should be masked by warming
the store or removing checks.
