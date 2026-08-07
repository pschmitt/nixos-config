---
name: resume-work
description: >-
  Figure out what a previous agent (Claude, Claude Work, or Codex) was last
  doing in this project and continue it. Use when the user starts a fresh
  session and asks to resume/continue previous work or pick up where things
  left off.
---

# Resume Work

Reconstructs the state of a previous agent's work in the current project
from raw session history and continues it. There is no shared handoff-note
convention to check — the previous agent's session transcript is the only
source of truth, scoped to the current project directory (`$PWD`).

## 1. Find the most recent prior session for this project

All three agents key their session storage by working directory, so start
there:

- **claude**: `~/.claude/projects/<slug>/*.jsonl`
- **claude-work**: `~/.config/claude-work/projects/<slug>/*.jsonl`
- **codex**: `~/.config/codex/sessions/YYYY/MM/DD/*.jsonl` (organized by
  date, not by project — find candidates with
  `rg -l '"cwd":"<absolute-pwd>"' ~/.config/codex/sessions/**/*.jsonl` or
  similar, scoped under `~/.config/codex/sessions`, not the whole home dir)

Where `<slug>` is `$PWD` with `/` replaced by `-` (matches the directory
names already under `~/.claude/projects/`).

**Exclude this session's own transcript** — it's being written to right now
so it will always sort as newest and is not useful history. For
claude/claude-work its filename is `${CLAUDE_CODE_SESSION_ID}.jsonl` if that
env var is set; skip it explicitly.

Sort the remaining candidates across all three locations by mtime and take
the most recent one.

## 2. Reconstruct the prior state

Read the chosen transcript's tail (last user/assistant turns, and any
task-list or plan state visible in it) to reconstruct:

- What the user originally asked for
- What was already done — verify against actual repo state, not just claims
  in the transcript; `git log`, `git status`, `git diff` are ground truth if
  they disagree with what the transcript says
- What was left unfinished

## 3. Continue the work

Briefly summarize your understanding of where things stand back to the user
before making changes, then continue from the concrete next step — don't
just re-verify everything from scratch.

If the user separately points you at a specific handoff note or summary
(e.g. one written by the `handoff` skill), read that directly instead — it
was written for exactly this purpose — but don't go looking for one at any
fixed or "latest" path; it only exists if the user hands you its path.
