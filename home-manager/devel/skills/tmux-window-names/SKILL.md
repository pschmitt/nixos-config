---
name: tmux-window-names
description: Inspect tmux windows and give them concise, useful names based on the work running in each pane. Use when asked to name, rename, or clean up tmux window names.
---

# Tmux Window Names

Name tmux windows from the work they contain, using the tmux MCP server when it is available and the `tmux` CLI otherwise.

## Inspect the target windows

- Check whether tmux is reachable by running a bounded tmux query such as `tmux list-sessions` or the preferred tmux MCP discovery tool. Do not treat an empty `$TMUX` or `$TMUX_PANE` in a subprocess as proof that tmux is inactive; execution tools often start a fresh shell without those variables.
- If tmux responds, continue with explicit session, window, and pane discovery. If no tmux server is reachable, report that and stop.
- Identify the requested scope. For “all windows”, inspect every window in the accessible tmux server; otherwise limit inspection and changes to the requested session or windows.
- Prefer tmux MCP tools for session, window, and pane discovery. When using the CLI, list sessions, windows, and panes with explicit session and window identifiers.
- Use pane titles, current commands, working directories, and pane count to infer each window's purpose. Do not infer purpose from the active window alone.
- Never target whichever window happens to be active when the requested window or session can be identified explicitly. When `$TMUX_PANE` is available, use it to identify the pane attached to this process. If it is unavailable, identify the relevant pane from discovered pane metadata, matching the conversation's working directory and command where possible; if multiple panes remain plausible, use a truthful name or ask which pane is intended instead of guessing.

## Choose and apply names

- Use a short, recognizable slug: lowercase words separated by hyphens, no spaces, at most 20 characters.
- Base names on concrete project, host, or task context visible in the panes. Prefer a project or task name over generic names such as `zsh`, `bash`, or `codex`.
- Keep an existing name when it already describes the window well, except when the user's request asks to rename every window.
- If the purpose is unclear, use a truthful name based on the visible shell or host rather than guessing a project.
- Rename only the requested windows, using explicit session and window targets. Then list the affected windows again to verify the resulting names.
