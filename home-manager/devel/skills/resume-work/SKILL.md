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

The agents key their session storage by working directory, so start there.
The project is not always `$PWD`: work on another repo (for example rbw or
browser-daemon) is often started from `nixos-config.git`. If the user names a
project, an agent or a config dir (`~/.config/claude-work`), search that one
instead of `$PWD`:

- **claude**: `~/.config/claude/projects/<slug>/*.jsonl` (the configured
  `CLAUDE_CONFIG_DIR`; `~/.claude/projects` only holds older sessions)
- **claude-work**: `~/.config/claude-work/projects/<slug>/*.jsonl`
- **codex**: `~/.config/codex/sessions/YYYY/MM/DD/*.jsonl` (organized by
  date, not by project — find candidates with
  `rg -l -g '*.jsonl' -F '"cwd":"<absolute-pwd>"' ~/.config/codex/sessions`,
  scoped under `~/.config/codex/sessions`, not the whole home dir)

- **agy** (Antigravity): `~/.gemini/antigravity-cli/conversation_summaries.db`
  has one row per conversation (`conversation_id`, `title`, `preview`,
  `workspace_uris`, `last_modified_time`). Pick candidates with
  `sqlite3 ~/.gemini/antigravity-cli/conversation_summaries.db "select
  conversation_id, last_modified_time, title from conversation_summaries where
  workspace_uris like '%<project>%' order by last_modified_time desc limit 5"`.
  Ignore the 2-step "Greeting" rows, they are usage probes. The transcript is
  `conversations/<id>.db`, table `steps`; payloads are protobuf, so read the
  tail as text with `sqlite3 <db> "select hex(step_payload) from steps order by
  idx desc limit 20" | xxd -r -p | tr -c '[:print:]\n' ' '`.

Where `<slug>` is `$PWD` with every `/` and `.` replaced by `-` (e.g.
`~/devel/nixos-config.git` → `-home-<user>-devel-nixos-config-git`; matches the
directory names already under `~/.config/claude/projects/`).

**Exclude this session's own transcript** — it's being written to right now
so it will always sort as newest and is not useful history. For
claude/claude-work its filename is `${CLAUDE_CODE_SESSION_ID}.jsonl` if that
env var is set; skip it explicitly.

Sort the remaining candidates across all locations by mtime and take
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

If the user separately points you at a specific handoff note or summary,
read that directly instead — it was written for exactly this purpose — but
don't go looking for one at any fixed or "latest" path; it only exists if the
user hands you its path. (The `handoff` skill writes no file: it types its
briefing straight into the new agent's prompt.)
