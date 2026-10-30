---
name: release
description: Use when releasing one of our own projects (rbw, browser-daemon, bruvtab, monarch) or when told to "do a release", cut a version, tag, publish an extension, or roll a new version out to the nixos-config hosts. Covers the order of steps, what to check first and how to consume the release.
---

# Release

The details of each repo are in its `AGENTS.md` and `justfile`; read them first. This skill is the
order of steps and the traps that cost rounds before.

## Before

1. `git status` is clean, `main` is pushed and lint is green. If lint fails, fix it first, then
   release (not the other way round).
2. Land open dependency PRs: `gh pr list`, merge those with green checks (Renovate rebases the
   conflicting ones; wait), skip failing or major ones and say so. Let CI finish on the resulting
   `main` (`nix` skill: `scripts/ci-wait.sh`).
3. Pick the version from the existing tags: `git tag --sort=-v:refname | head -3`. Do not skip a
   number (rbw once went to 2.27.2 without a 2.27.1). A change to the rbw agent protocol needs at
   least a minor bump. Any extension source change needs a new version.
4. Changelog: put the entries under the unreleased heading in `CHANGELOG.md` before
   `release-prepare`, which dates it. A forgotten changelog means editing the last release.
5. The tag is GPG-signed: run the unlock and probe from `CONTEXT.md` first.

## Release

- rbw, browser-daemon, bruvtab: `just release-prepare X.Y.Z`, then `just release-tag`
  (`tools/release.sh`, shared from `pschmitt/ci-workflows`). `release-tag` waits for green CI on
  HEAD and pushes the signed tag. The release workflow publishes, signs the extension (AMO, CRX),
  uploads assets (xpi, crx, docs images) and commits the package hashes to
  `browser/packages/metadata.json` on `main`.
- monarch: tag `vX.Y.Z` on `main` once CI is green; `.github/workflows/release.yml` builds amd64
  and arm64. There is no `just` recipe or `AGENTS.md` yet.
- Wait for the release workflow and the pin commit before consuming: `git pull --rebase`, then
  check the pin commit landed.

## After: roll it out

1. In `nixos-config`: `nix flake lock --update-input <rbw|browser-daemon|bruvtab|monarch>` on
   rofl-13 (`nix` skill), copy `flake.lock` back, commit, push, deploy to the affected hosts. The
   standing rule is commit, push and deploy without asking. rbw's `AGENTS.md` says to keep that
   lock bump local; the user's standing instruction wins, so push and mention it.
2. browser-daemon has its own `rbw` input. After each rbw release, pin it to the same commit as
   described in rbw's `AGENTS.md` ("Deploy").
3. Browser extensions: continue with the `extension-dev` skill to confirm gk4 and ge2 run the new
   version.
4. Report the tag, the release URL and what was deployed where; mention hosts that were off.
