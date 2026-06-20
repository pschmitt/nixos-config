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

## Deployment and operations

- To deploy host changes, use `just deploy TARGET_HOST`.
- For Home Assistant CLI access from this repo, prefer `zsh -lc 'zhj hass-cli ...'`.

## GPG and commit signing

- If a git commit fails because the GPG key is locked, run `zhj gpg::auto-unlock` to unlock it.
- `zhj gpg::auto-unlock` requires rbw to be unlocked. If it is not, use the `rbw` skill to unlock it first.

## Shell work

- Do not duplicate shell style rules here.
- For shell scripts, shell snippets, and zsh plugin work, use the `shell` skill as the source of truth.

## Tmux pane and window naming

- Once you understand what the current conversation is about, rename the active tmux pane and window to reflect it.
- Use the tmux MCP tools `rename-pane` and `rename-window` (load via ToolSearch if not yet available).
- To find the active window and pane: call `get-current-session`, then `list-windows` on the session, then `list-panes` on the active window.
- **Only rename if the current name looks like a default/generic shell name** (e.g. `claude`, `bash`, `zsh`, `fish`, `sh`, a bare number). If the window or pane already has a meaningful slug title, the user set it manually — leave it unchanged.
- Keep names short: max 20 characters, no spaces — use `-` as separator.
- Examples: `nix-ai-context`, `ha-lights`, `netbox-sync`, `ctx-tmux-rename`, `ha-fints-fix-reauth`
- Do this once per conversation, as soon as the topic is clear — do not repeat.
