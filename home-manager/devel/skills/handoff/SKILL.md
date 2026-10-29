---
name: handoff
description: >-
  Hand off the current work to a different agent (Codex, Claude, or Claude
  Work), spawned in a new tmux pane below this one, then stop all further
  work in this session. Use when the current agent is about to hit its usage
  quota/rate limit, or the user otherwise asks to "hand off", "pass this to
  another agent", or "continue this in a new pane".
---

# Handoff

Ends this agent's turn by spawning a different agent in a new tmux pane
below the current one, briefed on exactly what to continue.

## 1. Identify the current agent

Never offer the agent that is already running this session as a choice in
step 2. Determine it from the environment:

- `CLAUDECODE=1` set, `CLAUDE_CONFIG_DIR` unset or not pointing at
  `~/.config/claude-work` → current agent is **claude**
- `CLAUDECODE=1` set, `CLAUDE_CONFIG_DIR` pointing at `~/.config/claude-work`
  → current agent is **claude-work**
- `CLAUDECODE` unset (e.g. only `CODEX_HOME` present) → current agent is
  **codex**

## 2. Ask which agent should take over

Use AskUserQuestion (Codex: ask in a plain message and wait for the answer)
with the two remaining options from `codex`, `claude`,
`claude-work` (exclude whichever this session is). Briefly describe each
option as "start a new Codex session" / "start a new Claude Code session" /
"start a new Claude Code (work profile) session".

## 3. Compose the handoff briefing

No file, no temp path — compose the briefing as plain text now, in this
turn. It gets typed straight into the new agent's prompt once that agent has
loaded (step 5), nothing persists it anywhere and nothing else looks it up.

Write a concise but complete briefing, covering at minimum:

```markdown
# Handoff — <ISO 8601 timestamp>

From: <current-agent> (session <id if known, e.g. $CLAUDE_CODE_SESSION_ID>)
To: <chosen-agent>
Working directory: <absolute cwd>
Git: <branch>, <clean|dirty>, <ahead/behind info if relevant>

## Goal
<what the user originally asked for, in their own terms>

## Done so far
- <concrete, verifiable facts — commits made, files edited, commands run>

## In progress / next steps
- <the specific next action(s) — be concrete, not "continue the work">

## Relevant files
- path:line — why it matters

## Notes / gotchas
- <anything that would trip up a fresh agent: blocked on X, waiting for Y,
  don't touch Z, a decision already made and why>
```

If a task list, plan, or active loop exists for this session, fold its
current state into "In progress / next steps" rather than assuming the next
agent can see it — it can't.

## 4. Locate the current tmux pane

Use `$TMUX_PANE` (e.g. `%162`) as the current pane ID. Never pick the
*active* window or pane: that is whatever the user has focused, not
necessarily this agent's pane.

Tool shells may not inherit `$TMUX`/`$TMUX_PANE`, so check first that a tmux
server is reachable with a bounded query (`timeout 5 tmux list-sessions`).
If `$TMUX_PANE` is empty, find this agent's pane from
`tmux list-panes -a -F '#{pane_id} #{pane_current_path} #{pane_current_command}'`
by matching the working directory and agent command; if that doesn't give
exactly one pane, or no tmux server is reachable, tell the user handoff
requires running inside tmux and stop here without spawning anything.

## 5. Split a new pane, launch the chosen agent, then type the briefing in

Split directly below the current pane (tmux MCP `split-pane` with a
downward/vertical direction targeting the current pane, or fall back to
`tmux split-window -v -t <current-pane-id>`).

Launch the agent with no initial prompt argument — just `cd` and the bare
command — via tmux MCP `send-keys` (or plain
`tmux send-keys -t <new-pane-id> '...' Enter`):

```bash
cd '<same working directory>' && <agent-cmd>
```

Where `<agent-cmd>` is `claude`, `claude-work`, or `codex` matching the
user's choice from step 2.

These are TUI apps and take a moment to finish loading (auth, MCP servers,
etc). Poll the pane's content (tmux MCP `capture-pane`, or
`tmux capture-pane -t <new-pane-id> -p`) every couple of seconds until it
shows a ready input prompt instead of a loading/splash state, up to a
reasonable timeout (~30s).

Once ready, type the composed briefing from step 3 directly into the pane's
prompt and submit it — tmux MCP `set-buffer` + `paste-text`, or plain tmux
loading the buffer from stdin so quotes in the briefing need no escaping:

```bash
tmux load-buffer -b handoff - <<'EOF_BRIEFING'
<briefing>
EOF_BRIEFING
tmux paste-buffer -d -b handoff -t <new-pane-id>
```

The text lands in the agent's own input box, not a shell command line. Follow
with an Enter (`send-enter`, or `tmux send-keys -t <new-pane-id> Enter`) to
submit it.

## 6. Halt all work in this session

This is mandatory, even if a goal, plan, or `/loop` is still active:

- Claude Code: if a dynamic loop is running, call `ScheduleWakeup` with
  `stop: true`; if a `CronCreate`-based autonomous loop is tied to this
  session, cancel it with `CronDelete`.
- Codex and others: stop any background job or loop you started in this
  session (kill its process).
- Do not take any further tool actions and do not resume the interrupted
  work, even if it looks incomplete — that is now the new agent's job.

Confirm to the user in one short message which agent was spawned and that
it received the briefing, then stop.
