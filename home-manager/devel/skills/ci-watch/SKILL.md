---
name: ci-watch
description: Wait for GitHub Actions or GitLab CI of a pushed commit without wasting tokens. Use right after every `git push`, whenever you would otherwise check CI, poll `gh run list`, `gh pr checks` or `glab ci status`, or write a wait loop.
---

# CI watch

Waiting for CI must cost almost no tokens. Let the harness do the waiting and wake you; do not poll from inside your turn.

## The rule

Start **one** watch per pushed commit, in the background, then carry on with independent work or end your turn. Do not:

- run `gh run list`, `gh run watch`, `gh pr checks`, `glab ci status` or `glab ci view` repeatedly to see whether CI is done;
- write your own `while`/`sleep` loop, or ask the shell tool to block for minutes;
- start a second watch for the same commit, or re-watch after every small push (use `--follow` once instead);
- narrate "still pending" between checks.

## How

```bash
# once, after pushing, as a background command (it wakes you when it exits)
~/.config/claude/skills/ci-watch/scripts/ci-wait.sh --follow
```

- With Claude Code, run it with `run_in_background` (or via Monitor); you are re-invoked when it exits and need not poll its output. In other harnesses use their equivalent background or notification mechanism. If there is none, make one check after a reasonable interval and report that CI is still pending.
- `--follow` switches to the newest remote head of the branch when you push again, so one watch covers a series of pushes.
- The forge comes from the `origin` URL (GitHub for github.com, GitLab otherwise, e.g. git.wiit.one); override with `--forge github|gitlab`.
- Pass a commit, `--repo OWNER/REPO`, `--timeout SECONDS` (default 1800) or `--grace SECONDS` (wait for runs to appear, default 120) when needed.

## Exit codes

| Code | Meaning | What to do |
| --- | --- | --- |
| 0 | all runs succeeded | report it in one line |
| 1 | a run or pipeline failed (name and id on stderr, with the inspect command) | read a bounded log tail, fix, push, and start a new watch |
| 3 | timeout | report CI as still pending; do not restart blindly |
| 4 | no runs registered | the push has no workflow or pipeline; say so and move on |

CI logs can contain secrets: read only a bounded tail of a failed run, and follow `leaked-credentials` if one shows up.
