# Overlay review

Review date: 2026-11-06. Nixpkgs revision:
`b1b875982b17dabde9b4a37f3e229e74913e6db3`.

The maintenance policy lives in [overlays/AGENTS.md](../overlays/AGENTS.md).
Review temporary fixes on each relevant input update and at least monthly;
the next calendar review is due by 2026-12-06. This is a maintenance rule,
not a claim that a scheduled job performs the review automatically.

## Removed workarounds

Unmodified Nixpkgs packages for the following overrides were successfully
realized on an x86_64 Linux worker. Nix used valid binary substitutes where
available; these are not claims that every upstream test suite was rerun.
The builds retained the checks configured by Nixpkgs.

| Package | Removed local workaround |
| --- | --- |
| Audacity | Disable QML unity compilation |
| Squeekboard | Rewrite the Rust `close` return type |
| pipx | Extra test exclusions and forced Python 3.13 package selection |
| python-aodhclient | Disable Python distribution metadata checks |
| diff-cover | Exclude six HTML snapshot tests |
| websockify | Exclude two JWT tests |
| torchcodec | Exclude the audio comparison test |
| rxvt-unicode | Force GNU C++17 |
| shadowsocks-libev | Suppress discarded-qualifier errors |
| Perl DBD::CSV | Disable the entire test suite |

Both the Python 3.13 pipx package and the canonical top-level pipx package were
checked. These removals restore Nixpkgs' package selection and checks rather
than introducing replacement workarounds.

## Retained fixes

| Package | Current evidence and removal condition |
| --- | --- |
| home-assistant-cli | Nixpkgs already supplies 1.0.0. Remove the development source pin, fixture rewrite and `test_defaults` exclusion. Retain only the Python 3.14 event-loop correction until upstream uses the supported asyncio API. |
| Playwright Python | The unmodified source fetch still fails with a hash mismatch. Retain the corrected source hash until the pinned expression matches the fetched source. |
| pytest-playwright | `doCheck = false` still accompanies a `preCheck` reference that pulls browser binaries into the derivation. Retain the narrow hook override until Nixpkgs removes that unnecessary dependency. |
| playwright-mcp | Unmodified WebKit fails auto-patchelf because `libmanette-0.2.so.0` is missing. Retain the master package substitution until the main input contains the dependency fix. |
| obs-replay-source | The unmodified build fails on deprecated `obs_properties_add_button` with OBS 32.2.2. Retain the API correction until the plugin or Nixpkgs includes it. |
| pysaml2 | The Python 3.13 build reproduces 42 failing XML sandbox tests without the patch (734 pass); the patched build passes all 776 enabled tests. Retain the XMLResource correction until upstream's xmlschema 4 support reaches the pin. |
| xmlschema | A real zope.interface provider descriptor on an inherited validator reproduces `AttributeError: __provides__`. The regression and 1,522 package tests pass with the patch. Retain the descriptor guard until upstream includes it. |
| Matrix Synapse | The packaged SAML extra omits `pytz`. Retain the dependency correction until the package supplies the complete extra. |
| Noctalia | Four image, keyboard and capture corrections form a patch bundle consumed at explicit positions by its package overlay. The complete 19-patch series still applies to the pinned source. Remove individual corrections when upstream implements them. |

## Package customization boundaries

- `rbw.nix` selects the project's own flake overlay.
- `lan-mouse.nix` owns the chosen keymap and input-state integration.
- `pytr.nix` deliberately selects an installed Chromium-compatible browser from
  PATH; the upstream source still expects a Playwright-managed browser. This
  integration is preserved, not counted as an obsolete fix removed.
- `go-task.nix` owns the executable and completion rename to avoid a Taskwarrior
  collision. Its disabled install check is tied to the rename, not an upstream
  package failure.
- `wireguard-tools.nix` adds `wg-json`. Parenthesizing the fallback preserves any
  future upstream install hook; the current pin has no such hook.
- `zsh-completions.nix` deliberately tracks the configured upstream source input.
- Noctalia's temporary corrections live in `hotfixes/noctalia.nix`; its deliberate
  plugin API, caffeine, OSD and notification feature additions remain in `noctalia.nix`.
  The extraction preserves all patch paths and their exact order.

## Validation boundaries

All 26 NixOS configurations, including installation images, evaluate to system
derivations. Fourteen retained package/integration derivations match the baseline
exactly, including both Playwright package sets and Noctalia. Noctalia's 19 patch
names, order and content hashes also match independently.

The candidate hass-cli, OBS replay plugin, pytr, Playwright, pytest-playwright,
pysaml2 and xmlschema outputs were built on x86_64 Linux. Hass-cli reports 1.0.0
and pytr's help command succeeds without contacting external services. The
patched pysaml2 tests also pass on Python 3.14. These checks do not claim ARM
builds or GUI interaction tests.

The broad `nix flake check --no-build` fails identically on baseline and candidate
while evaluating the Termux bundle: an invalid `hm_.configzsh.zprofile.drv` path.
This pre-existing failure is separate from the successful NixOS evaluations;
the full Termux bundle is not validated by this review.

Package checks and evaluations run on a disposable worker, never on the local
agent host. Runtime smoke checks must not contact a bank, change Home Assistant
state, or mutate other live services. Package build success alone does not
prove a downstream integration fix obsolete: the xmlschema regression above
is an example of why a focused reproducer is necessary.
