# Repository AI Context

Use this file as lightweight shared context for AI tooling in this repository.

## General rules

- Read `AGENTS.md` and follow it as the primary repository instruction source.
- Prefer repository skills when a task matches one:
  - `shell` for bash, `sh`, and zsh
  - `nix` for NixOS and Home Manager work
  - `home-assistant`, `netbox`, `jira`, `confluence`, `obsidian`, `n8n`, `zpl`, and other repo-local skills when applicable

## Code and validation

- Keep changes minimal and targeted.
- Preserve existing user changes; do not revert unrelated edits.
- Format and lint with the repo-standard tools for the language or domain you touch.
- For Nix changes, use `nixfmt` and run `statix check` from within `nix develop`.
- Never introduce trailing whitespace.

## Command safety

- Do not start unbounded filesystem traversals. Prefer `rg --files` or a targeted `rg` search over `find`, `bfs`, or similar recursive discovery commands.
- If `find`, `bfs`, or another potentially expensive recursive command is necessary, scope it to the smallest relevant directory, exclude known large/generated paths, and wrap it with `timeout 5m`.
- Never recursively search broad paths such as `/`, a home directory, or `/nix/store`. If a scoped search times out, refine its scope rather than rerunning it unchanged.

## Deployment and operations

- Almost always avoid running expensive build commands (for example `cargo build` or Nix host configuration evaluations) on the local host where the agent is running. When possible, build on a `rofl-*` host instead; `rofl-13` and `rofl-14` are preferred.
- Remote build directories on `rofl-13` and `rofl-14` should use `~/build/<PROJECT_NAME>`.
- To deploy host changes, use `just deploy TARGET_HOST`.
- For Home Assistant CLI access from this repo, prefer `zsh -lc 'zhj hass-cli ...'`.

## Version control workflow

- Do not open pull requests unless explicitly requested. Default to working directly on `main` (or the repository's default branch) without creating feature branches or PRs.

## Progress notifications

- For substantial multi-step work or long-running operations, check the user's presence in Home Assistant when it affects whether they can see chat updates. Use the HA live-context tool or `zsh -lc 'zhj hass-cli state list person'` to inspect the relevant `person.*` state. When the user is away, send concise Signal updates through Home Assistant using `notify.signal_me` (`zsh -lc 'zhj hass-cli service call notify.signal_me --arguments "message=..."'`).
- Send Signal messages for meaningful milestones, blockers that need the user's attention, and completion after a long operation. Keep routine progress in chat, avoid duplicate messages, and don't send for quick tasks.
- Start every Signal update with an uppercase ASCII task/topic and the actual harness name in `[TOPIC | HARNESS]` form on its own first line, for example `**[FNUC UPGRADE | CODEX]**`. This lets the user distinguish updates when agents are working in parallel; use the task topic to distinguish agents on the same harness, and don't invent a harness or agent identity. The HA Signal wrapper applies caller-supplied `**bold**` and `*italic*` formatting as actual Signal styles; messages without markers remain plain. When calling the sender script directly, pass `--no-format` to preserve markup literally.
- State what changed or what is blocked and the next step. Keep secrets and sensitive identifiers out of notifications. If Home Assistant is unavailable, continue communicating in chat.

## GPG and commit signing

- If a git commit fails because the GPG key is locked, run `zhj gpg::auto-unlock` to unlock it.
- `zhj gpg::auto-unlock` requires rbw to be unlocked. If it is not, use the `rbw` skill to unlock it first.

## Shell work

- Do not duplicate shell style rules here.
- For shell scripts, shell snippets, and zsh plugin work, use the `shell` skill as the source of truth.

## Tmux pane and window naming

- Always check whether tmux is reachable with a bounded query such as `tmux list-sessions`, even when `$TMUX` or `$TMUX_PANE` is empty; tool shells may not inherit those variables. If no tmux server is reachable, skip naming.
- Once you understand what the current conversation is about, identify and rename only this agent's own tmux window so its name reflects this work. Use `$TMUX_PANE` to identify this agent's pane when available. When it is unavailable, use discovered pane metadata and match the conversation's working directory and command where possible. Do not guess from whichever window is active.
- For a request to rename all windows or another broader scope, use the `tmux-window-names` skill and follow its discovery and verification steps.
- Use the tmux MCP tools `rename-pane` and `rename-window` (load via ToolSearch if not yet available).
- **Do not target tmux's "active" pane/window** when the requested target can be identified explicitly. Active means whichever window the user currently has focused, which may differ from the one this agent is using.
- Keep an existing name only when it accurately describes this agent's current work. If the user asks to rename all windows, follow the `tmux-window-names` skill.
- Keep names short: max 20 characters, no spaces — use `-` as separator.
- Examples: `nix-ai-context`, `ha-lights`, `netbox-sync`, `ctx-tmux-rename`, `ha-fints-fix-reauth`
- Do this once per conversation, as soon as the topic is clear — do not repeat.
