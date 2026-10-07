---
name: tmux-window-names
description: Inspect tmux windows and give them concise, useful names based on the work running in each pane. Use when asked to name, rename, or clean up tmux window names.
---

# Tmux Window Names

Name tmux windows from the work they contain, using the tmux MCP server when it is available and the `tmux` CLI otherwise.

## Inspect the target windows

- Always check whether tmux is reachable by running a bounded tmux query such as `tmux list-sessions` or the preferred tmux MCP discovery tool. **Never skip this check or stop the task just because `$TMUX` or `$TMUX_PANE` is empty.** Execution tools often start a fresh shell without those variables, so their absence says nothing about whether a tmux server is running. Treat `$TMUX` and `$TMUX_PANE` only as hints for identifying the attached session and pane when they are available.
- If tmux responds, continue with explicit session, window, and pane discovery. If no tmux server is reachable, report that and stop.
- Identify the requested scope. For “all windows” or equivalent, inspect every window in every accessible session and rename each one, even when its existing name is meaningful. For a narrower request, limit inspection and changes to the requested session or windows.
- Prefer tmux MCP tools for session, window, and pane discovery. When using the CLI, list sessions, windows, and panes with explicit session and window identifiers.
- Use pane titles, current commands, working directories, and pane count to infer each window's purpose. Do not infer purpose from the active window alone.
- Never infer a window's purpose from whichever window happens to be active. When `$TMUX_PANE` is available, use it to identify the pane attached to this process. If it is unavailable, use pane metadata, matching the conversation's working directory and command where possible; if multiple panes remain plausible, use a truthful name instead of guessing.

## Choose and apply names

- Use a short, recognizable slug: lowercase words separated by hyphens, no spaces, at most 20 characters.
- Base names on concrete project, host, or task context visible in the panes. Prefer a project or task name over generic names such as `zsh`, `bash`, or `codex`.
- For a narrower request, keep an existing name when it already describes the window well. When the user asks to rename every window, assign a purpose-based name to each one.
- If the purpose is unclear, use a truthful name based on the visible shell or host rather than guessing a project.
- Rename the windows in scope using explicit session and window targets. Then list the affected windows again to verify the resulting names.
