# Repository AI Context

Use this file as lightweight shared context for AI tooling in this repository.

## General rules

- Read `AGENTS.md` and follow it as the primary repository instruction source.
- Prefer repository skills when a task matches one:
  - `shell` for bash, `sh`, and zsh
  - `nix` for NixOS and Home Manager work
  - `signal-notify` before sending any Signal message, `secret-hygiene` before commands that may print credentials, `leaked-credentials` the moment a credential is exposed, `browser-daemon` before browser work, `browser-login` for any login in a browser session, `gpg-signing` before signed commits or tags, `tmux-window-names` for naming tmux windows
  - `brkn-infra` to learn which host does what (build, test and deploy targets, Android devices) before you name or pick a host, `release` for releasing rbw, browser-daemon, bruvtab or monarch, `extension-dev` for browser extension work, `skill-suggestions` to review past sessions and propose skills
  - `ha`, `netbox`, `jira`, `confluence`, `obsidian`, `n8n`, `zpl`, and other repo-local skills when applicable
- Watch for toil worth capturing (the same friction twice, a rediscovered procedure, a generalizing user correction). Say so at the end of the task and propose a skill or skill update with the `self-improvement` skill; ask before creating a new skill.
- Linkify references whenever a useful target is available. This applies across
  all kinds of work, including GitLab merge requests, GitHub pull requests,
  tickets, documentation, dashboards, and local files. In terminal output, use
  OSC 8 hyperlinks (`ESC ] 8 ;; URL ESC \ label ESC ] 8 ;; ESC \`) instead of
  bare URLs or IDs; in Markdown-capable output, use Markdown links.

## Concord

- Concord MCP is available in every repository. Before editing, call `start_work` with the task and the files or modules you expect to touch; it claims them and reports overlaps with other agents, so resolve overlaps first.
- Use `inspect_work` to see who else is here, `update_work` for progress and messages to other agents, `transfer_work` for handoffs, and `finish_work` with the outcome, changed files and tests before finishing.
- Concord needs no files in the repository: do not run `concord setup` yourself.

## Host awareness

- Always be aware of which host you are currently running on (`hostname` or `$HOST`). In this environment, agents frequently run directly on `fnuc` (or workstations like `gk4`, `ge2`, `x13`).
- **Never SSH into the current host**: do not run `ssh fnuc ...` (or `localhost`, `fnuc.lan`, etc.) when already running on `fnuc`. Execute commands locally instead of establishing a redundant SSH connection to yourself.
- Before executing commands aimed at a specific host (such as checking systemd units, containers, logs, or local files), check whether you are already on that host and run them directly.

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
- Once a change is done and verified, commit it, push it to the default branch and deploy it to the affected hosts without asking. Leave unrelated modified or untracked files out of the commit.
- After pushing to `nixos-config-private`, immediately update the public repo's `flake.lock` (`nix flake lock --update-input nixos-config-private`, run on rofl-13, copy `flake.lock` back) and commit it as `bump my privates`, then push.

## Progress notifications

- For substantial multi-step or long-running work, the user may be away from the chat. Load the `signal-notify` skill before sending any Signal message; it covers the presence check, when to send and the format.

## GPG and commit signing

- Before creating any GPG-signed commit or tag (including amend, cherry-pick, and rebase), load the `gpg-signing` skill and unlock the key first. Never retry with interactive pinentry or disable signing; a curses pinentry prompt can corrupt the agent's terminal UI.

## Leaked credentials

- Keep secret values out of tool-call arguments, tool output, transcripts and chat; pass them by file, stdin or environment and mask them when diffing or listing.
- Load the `secret-hygiene` skill before running commands that may print credentials (Home Assistant config, `ps`/`env`, `rbw`, SOPS diffs, `openstack`, `journalctl`, browser snapshots). The `agent-secret-guard` and `agent-secret-scan` hooks enforce the Bash cases; if a command is blocked, use the suggested safe form and do not work around the hook.
- If a credential ends up somewhere it should not be, even briefly and even if you caused it, load the `leaked-credentials` skill now and follow it; do not wait for the end of the task. Once contained, propose an update to the relevant skill, `CONTEXT.md`, `AGENTS.md` or hook so the same leak does not happen again.

## Browser MCPs

- Load the `browser-daemon` skill before the first `browser_*` call (node and profile choice, session labelling, session management).
- Never read a cookie or token through a browser tool, and never type a password, token or TOTP code with `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`: the MCP echoes every call into the transcript and logs. Load the `browser-login` skill for any login (`browser_fill_secret`, `browser_fetch`, `browser_ask_human`).

## Shell work

- Do not duplicate shell style rules here.
- For shell scripts, shell snippets, and zsh plugin work, use the `shell` skill as the source of truth.

## Tmux pane and window naming

- As soon as the task is clear, and again whenever the conversation changes topic meaningfully, load the `tmux-window-names` skill and rename only this agent's own window (identified via `$TMUX_PANE`, never the active window).
