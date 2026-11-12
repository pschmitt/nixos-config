---
name: release
description: Use when releasing one of our own projects (rbw, browser-daemon, bruvtab, monarch) or when told to "do a release", cut a version, tag or publish an extension. Covers the order of steps, what to check first and how to consume the release. Not for "deploy" (that means bumping the flake input and rolling out to the hosts, without a release, see the `deploy` skill).
---

# Release

The details of each repo are in its `AGENTS.md` and `justfile`; read them first. This skill is the
order of steps and the traps that cost rounds before.

## Before

1. `git status` is clean, `main` is pushed and lint is green. If lint fails, fix it first, then
   release (not the other way round).
2. Coordinate first: check Concord (`inspect_work` on the repository's workspace) for other agents
   working in it, ask them through `update_work` whether their work is pushed and in the changelog,
   and tell them not to push until the tag is out. Verify pushed state yourself (`git log`,
   `git status`) when they are not live.
3. Get the Renovate (and other dependency) PRs in: `gh pr list`. Merge the green ones; rebase a
   conflicting one (tick its rebase box, or wait for Renovate) and merge it once green; fix a
   failing one when the fix is small (`merge-prs` skill). Only skip one that needs a real
   migration or a major update, and say which and why. Let CI finish on the resulting `main`
   (`ci-watch` skill).
4. Pick the version from the existing tags: `git tag --sort=-v:refname | head -3`. Do not skip a
   number (rbw once went to 2.27.2 without a 2.27.1). A change to the rbw agent protocol needs at
   least a minor bump. Any extension source change needs a new version.
5. Changelog (when the project has one): it should already be current, because every change adds
   its entry under the unreleased heading in the same commit. Before `release-prepare`, which
   dates it, check that each commit since the last tag (`git log vLAST..`) is covered, add what
   is missing (merged dependency PRs, other agents' work), and merge entries for intermediate
   steps into what actually ships. A forgotten changelog means editing the last release.
6. The tag is GPG-signed: run the unlock and probe from `CONTEXT.md` (`gpg-signing` skill) right
   before every signed commit and again right before `release-tag`; the cache can expire while
   CI runs.

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

1. Follow the `deploy` skill for the rollout (bump the input in `nixos-config` on an `rworker`,
   commit, push, deploy to the affected hosts). The standing rule is to do this without asking;
   rbw's `AGENTS.md` says the same.
2. browser-daemon has its own `rbw` input. After each rbw release, pin it to the same commit as
   described in rbw's `AGENTS.md` ("Deploy").
3. Browser extensions: continue with the `extension-dev` skill to confirm gk4 and ge2 run the new
   version.
4. Report the tag, the release URL and what was deployed where; mention hosts that were off.
