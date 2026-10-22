#!/usr/bin/env bash
# SessionStart hook: give this agent's tmux window a short name from the project
# directory. Only touches windows still on automatic-rename; once renamed (by this
# hook, the agent or the user) tmux turns automatic-rename off, so later sessions
# in the window keep the more specific name.

[[ -n "${TMUX_PANE:-}" ]] || exit 0

auto="$(tmux display-message -p -t "$TMUX_PANE" '#{automatic-rename}' 2>/dev/null || true)"
[[ "$auto" == 1 ]] || exit 0

cwd="$(jq -r '.cwd // empty' 2>/dev/null || true)"
name="$(basename -- "${cwd:-$PWD}")"
name="${name%.git}"
name="${name//[[:space:]]/-}"
name="${name:0:20}"
[[ -n "$name" ]] || exit 0

tmux rename-window -t "$TMUX_PANE" "$name"
