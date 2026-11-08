---
name: git-commit
description: Create git commits safely when other agents may share the same checkout and git index. Use before every git commit (including amend, revert, cherry-pick and lock-file bumps), before staging with git add or git rm, and when a commit picked up or left behind changes it should not have.
---

# Git commit

Several agents often work in one checkout (for example `nixos-config`) and so
share one git index. Whatever is staged when someone runs `git commit` goes
into that commit. A file you stage and leave staged can end up in another
agent's commit, and theirs in yours.

## Commit only your own paths

- Commit by explicit path: `git commit -m "..." -- <path>...`. With paths,
  git commits exactly those paths as they are in the working tree and leaves
  everything else in the index alone, staged or not.
- Name deleted and renamed files too: `git rm <path>` followed by
  `git commit -- <path>`, or for a rename both the old and the new path.
- A new file must be known to git first: `git add <file>` (or `git add -N`),
  then commit it by path.
- Do not stage now and commit later. Stage right before the commit, in the
  same step, so nothing of yours sits in the shared index.
- Never `git add -A`, `git add .`, `git commit -a` or a bare `git commit` in a
  shared checkout.
- Before committing, `git diff --cached --stat` shows what is staged. Leave
  staged files that are not yours alone; do not unstage or commit them.
- Afterwards, `git show --stat HEAD` must list exactly your files. If one is
  missing, look for it in recent commits (`git log --oneline -3 -- <path>`):
  another agent may have committed it. Say so in your report.

## Before and after

- Get up to date first: `git pull --rebase --autostash`. If another agent is
  in the middle of a rebase or merge (`git status`), wait and ask it through
  Concord instead of continuing it.
- Signed commits and tags: load the `gpg-signing` skill first. Never sign
  through an interactive pinentry and never disable signing.
- Pre-commit hooks run on the commit. Do not bypass them with `--no-verify`;
  fix the cause (in `nixos-config`: `just dev-hooks` when the hook binary is
  missing).
- Push right after committing. If the push is rejected, pull with rebase and
  push again; never force-push the default branch.

## Message

- Follow the style in `git log` of the repository: a short summary line, a
  body for the why when it is not obvious.
- End with the attribution lines that the harness gives for commits.
- Repository rules come first, for example `bump my privates` for the
  private-input lock bump in `nixos-config`.
