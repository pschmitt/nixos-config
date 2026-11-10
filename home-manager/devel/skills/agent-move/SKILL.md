---
name: agent-move
description: >-
  Move the running agent conversation (Claude Code or Codex) to another host
  and resume it there with its full context. Use when the user says "move
  this session to <host>", "continue this on fnuc", "I need to shut down this
  laptop but keep the conversation", or wants to resume a session on a
  different machine. Not for same-host handoffs (see `handoff`) or summaries
  of old work (see `resume-work`).
---

# Agent move

Copies the session transcript to the same path on the target host and runs
`claude --resume <id>` (or `codex resume <id>`) in a new tmux window there.
The conversation context is kept in full; nothing is summarised.

## What moves and what does not

- Moves: the transcript (`projects/<cwd-encoded>/<id>.jsonl`, plus the
  `<id>/` directory with subagent and tool-result files).
- Does not move: uncommitted files, running processes and background tasks,
  shell state, loops and cron jobs, MCP server state, the prompt cache
  (the first turn after resuming is slower and costlier).
- The working directory must exist at the **same absolute path** on the
  target, because Claude encodes the cwd into the project folder name.

## Procedure

1. Pick the target host (see `brkn-infra`); never the current host.
2. Get the session id: `$CLAUDE_CODE_SESSION_ID` for Claude Code. For Codex,
   use the id from the rollout file name under `~/.codex/sessions/`.
3. Make the work reachable on the target: commit and push (a WIP commit is
   fine) or rsync the tree. Pull it on the target before resuming.
4. Stop anything that must not run twice: `ScheduleWakeup` with `stop: true`
   or `CronDelete` for loops, and background jobs.
5. Dry-run, then run:

   ```bash
   scripts/agent-move.sh --dry-run SESSION_ID TARGET_HOST
   scripts/agent-move.sh SESSION_ID TARGET_HOST          # Claude Code
   scripts/agent-move.sh --agent codex SESSION_ID TARGET_HOST
   ```

   `--no-launch` only copies and prints the resume command.
6. Tell the user the tmux window name on the target, and stop working in the
   source session: two live copies of one session diverge.

## Pitfalls

- A session that is still open on the source keeps appending to its own
  file. Copy at a quiet point (end of your turn) and do not keep talking in
  the original afterwards.
- `claude --resume` on the target needs the same `CLAUDE_CONFIG_DIR`
  layout. The script assumes the same config path on both hosts.
- If the target is offline or has no tmux server, use `--no-launch` and
  resume by hand.
- Work-profile sessions live under `~/.config/claude-work`; run the script
  with `CLAUDE_CONFIG_DIR` set to that directory.
