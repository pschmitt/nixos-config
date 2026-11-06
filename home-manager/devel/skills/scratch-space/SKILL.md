---
name: scratch-space
description: Where to put large temporary files (repository clones, exports, APKs, snapshots, test copies, build trees) and agent logs without filling RAM. Use before creating any sizeable temp file or directory, and when cleaning up after a task.
---

# Scratch space for large files

`/tmp` (including the agent scratchpad under it) and `$XDG_RUNTIME_DIR`
(`/run/user/$UID`) are often RAM-backed tmpfs. Large files left there fill RAM
and swap. Keep them out.

## Where files go

| Kind of file | Location |
|---|---|
| Large, regenerable artifacts: clones, exports, APKs, snapshots, test copies, build trees | `${XDG_CACHE_HOME:-$HOME/.cache}/agents/<PROJECT_NAME>/` |
| Logs and state that must outlive a cache cleanup | `${XDG_STATE_HOME:-$HOME/.local/state}/agents/<PROJECT_NAME>/` |
| Durable data an agent produces | `${XDG_DATA_HOME:-$HOME/.local/share}/agents/<PROJECT_NAME>/` (rarely needed) |
| Heavy builds and test suites | An ad-hoc `rworker` VM (see the `rworker` skill), not this host |
| Quick one-off builds on a shared build host | `~/build/<PROJECT_NAME>` on that host (see the private `brkn-infra` skill) |

- Use one shared `agents/` folder for all tools (Claude, Codex, ...), so
  checkouts can be reused and cleaned up in one place.
- Small files (scripts, short outputs) may still go in the session scratchpad.

## Rules

- Never put clones, exports, APKs, snapshots or test copies in `/tmp` or
  `$XDG_RUNTIME_DIR`.
- Delete your own temporary files and directories when you are done.
- On a shared build host, remove only what you can identify as left by your own
  earlier runs; never delete another agent's files or anything whose owner is
  unclear. Prefer an agent- or run-specific directory, and never sync with
  deletion into a shared directory.
- Check `du -sh` of your directory before and after large jobs.
