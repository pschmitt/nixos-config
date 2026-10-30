---
name: extension-dev
description: Use when changing, building, installing or testing a browser extension of ours (rbw-browser, the browser-daemon node extension, bruvtab) and getting the new version running in Firefox or Chromium on gk4, ge2 or fnuc. Covers version checks, stale add-ons, powered-off laptops and icon work.
---

# Browser extension dev loop

Our extensions are Nix-managed and signed by AMO and CRX at release time. A change only reaches the
browser through a version bump, a release and a deploy. Most "my fix does not show up" reports are
a stale browser, not a bad build.

| Extension | Source | Firefox id / Chromium id |
|---|---|---|
| rbw-browser | `~/devel/private/pschmitt/rbw.git/browser/` (shares rbw's version) | `rbw-browser@pschmitt.dev` |
| browser-daemon node | `~/devel/private/pschmitt/browser-daemon.git/browser/extension/` | `browser-daemon-node@pschmitt.dev` / `cjbnnociajogjgnpihfkhnbehmkdpijf` |
| bruvtab | `~/devel/private/pschmitt/bruvtab.git/bruvtab/extension/` | see its `AGENTS.md` |

Read the repo's `AGENTS.md` and `docs/browser.md` (rbw) before building.

## Loop

1. Edit the extension. Any source change needs a new version, because AMO signs each version only
   once. Use the `release` skill for the version, tag and signing.
2. Build and test on rofl-13, not locally (`nix` skill, `scripts/remote-sync.sh`). Unsigned
   builds: `python3 browser/build.py` in rbw creates `browser/dist/` and unsigned ZIPs. For a quick
   look, Firefox loads `browser/dist/firefox/manifest.json` from `about:debugging#/runtime/this-firefox`;
   Chromium loads the unpacked directory with developer mode on. `browser/install.py` registers the
   native host for such a manual install. The user usually wants the latest build on gk4 and ge2
   without asking: after a release, bump the flake lock and `just deploy gk4` / `just deploy ge2`.
3. Check what the browser actually runs, per host, before saying it is deployed:

   ```
   ssh -n gk4 'ls ~/.config/chromium/Default/Extensions/<chromium-id>/'      # version directories
   ssh -n gk4 'for p in ~/.mozilla/firefox/*/extensions/<firefox-id>.xpi; do unzip -p "$p" manifest.json | jq -r .version; done'
   ```

4. A running browser keeps the old version. Chromium must be restarted (gk4 stayed on 0.3.8 after a
   0.3.10 deploy); Firefox may need a restart after Home Manager has replaced the xpi, and a
   profile can pin an older add-on. Say which restart the user must do instead of retrying.
5. Test in the real browser. On gk4 you may drive the desktop with the hypruse MCP (the user
   allows it); use `ssh gk4` directly for shell work. Playwright against an extension node is
   possible but not set up as a default.

## Hosts that are off

gk4 and ge2 are laptops or desktops that are often powered off. Test with
`ssh -o ConnectTimeout=8 -o BatchMode=yes HOST true`. If a host is off, do not loop on it. Finish
the rest, tell the user which hosts still need `just deploy HOST`, and send the Signal update only
as the `signal-notify` skill allows.

## Icons, badges and layout

The user iterates on these a lot; save rounds by checking up front:

- Toolbar icons look tiny. Use a variant without the round background and the outline (the rbw
  toolbar icons are the model), and check it at 16, 32 and 48 px in the real toolbar.
- Count or state badges go in the top-right corner, a plain dot for state (blue for connected),
  and must not sit low or overlap the icon.
- When something appears in a header (a chevron, a back button), the icon next to it must not
  shift. Test with and without it.
- Show screenshots or the icon preview to the user and wait for a go-ahead before committing
  visual assets.
- Firefox popups: check that the window is not cropped and does not jump between two widths.
