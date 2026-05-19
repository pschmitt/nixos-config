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

## Shell work

- Do not duplicate shell style rules here.
- For shell scripts, shell snippets, and zsh plugin work, use the `shell` skill as the source of truth.
