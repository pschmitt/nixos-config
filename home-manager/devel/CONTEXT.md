# Repository AI Context

Use this file as lightweight shared context for AI tooling in this repository.

## General rules

- Read `AGENTS.md` and follow it as the primary repository instruction source.
- Prefer repository skills when a task matches one:
  - `shell` for bash, `sh`, and zsh
  - `nix` for NixOS and Home Manager work
  - `ha`, `netbox`, `jira`, `confluence`, `obsidian`, `n8n`, `zpl`, and other repo-local skills when applicable

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

- For substantial multi-step work or long-running operations, check the user's presence in Home Assistant when it affects whether they can see chat updates. Use the HA live-context tool or `zsh -lc 'zhj hass-cli state list person'` to inspect the relevant `person.*` state. When the user is away, send concise Signal updates. Prefer the `signal` MCP (`send_message` with `recipient="me"`; `list_recipients` shows the names) and fall back to Home Assistant when it is not available (`zsh -lc 'zhj hass-cli service call notify.signal_me --arguments "message=..."'`).
- Send Signal messages for meaningful milestones, blockers that need the user's attention, and completion after a long operation. Keep routine progress in chat, avoid duplicate messages, and don't send for quick tasks.
- Start every Signal update with an uppercase ASCII task/topic and the actual harness name in `[TOPIC | HARNESS]` form on its own first line, for example `**[FNUC UPGRADE | CODEX]**`. This lets the user distinguish updates when agents are working in parallel; use the task topic to distinguish agents on the same harness, and don't invent a harness or agent identity. Both the `signal` MCP and the HA Signal wrapper turn Markdown-ish markers into actual Signal styles: `**bold**`, `*italic*`, `~~strikethrough~~`, `||spoiler||`, `` `monospace` `` and fenced ```` ``` ```` blocks (monospace; Signal has no real code block). Styles nest, code is literal, and a backslash escapes a marker; messages without markers remain plain. Pass `format=false` to the MCP (or `--no-format` to the sender script) to preserve markup literally. Attach files or screenshots with the MCP's `attachments` argument. The MCP can also reply with a quote, react, edit and delete the bot's own messages (`send_message` returns the timestamp those need) and mention people with `@{name}`; it cannot read incoming messages.
- State what changed or what is blocked and the next step. Keep secrets and sensitive identifiers out of notifications. If Home Assistant is unavailable, continue communicating in chat.

## GPG and commit signing

- Before creating any GPG-signed commit or tag (including amend, cherry-pick, and rebase), run `zsh -lc 'zhj gpg::auto-unlock'`. By default the helper unlocks every signing key referenced by `user.signingkey` in the git configs (global, `includeIf`'d such as the work key, and the current repo), skips keys already cached in gpg-agent and returns immediately when all are cached. Pass a key ID or fingerprint (`zsh -lc 'zhj gpg::auto-unlock KEY_ID'`) to unlock only that key. Each key's passphrase comes from the rbw entry whose `Key ID` field matches; if none is found it fails with an error naming the key. Do this before invoking Git; a curses pinentry prompt can corrupt the agent's terminal UI.
- If unlocking requires rbw and the vault is locked, use the `rbw` skill to unlock it first. Never enter or capture a passphrase in an agent terminal, command argument, transcript, or chat.
- After auto-unlock, check the repository's actual signing key with a prompt-free signing probe: `gpg --batch --no-tty --pinentry-mode error --local-user "$(git config user.signingkey)" --detach-sign --output /dev/null </dev/null`. Require a configured `user.signingkey` and a successful probe before invoking Git. Keys that are not referenced by a git config `user.signingkey` can be unlocked by passing them to the helper explicitly. If the probe fails, resolve the unlock problem before proceeding; never retry with interactive pinentry or disable signing.
- Keep normal interactive GPG configuration intact. Any GPG wrapper used for agent Git signing must pass `--batch --no-tty --pinentry-mode error` so an expired cache fails without opening pinentry, and must be scoped to the agent command rather than installed as a global Git/GPG setting.

## Leaked credentials

- Keep secret values out of everything you can see or log: tool-call arguments, tool output, files the tools echo back (e.g. code passed to a browser tool is repeated in its output), transcripts and chat. Pass them by file, stdin, environment or a one-shot local channel instead, and mask them when diffing or listing.
- Prevention comes first. These commands caused most past leaks; use the safe form:
  - Home Assistant: never read `.storage/core.config_entries`, `.storage/auth` or `secrets.yaml`, and never `rg`/`grep` `/mnt/ha` without `-l` or a `--glob '!...'` that excludes them. Use `zsh -lc 'zhj hass::config-entries [--domain X]'` (key names only) and `zhj hass::check-config` instead of `ha core check`. Filter `ha core logs`/`ha apps info` with `jq` or `grep -v` on named fields.
  - Processes: no `ps aux`, `ps -ef`, `pgrep -a`, or `/proc/*/cmdline` (signed browser URLs, `--passwd` arguments). Use `pgrep -l NAME`, `pgrep -c NAME` or `ps -o pid,etime,comm -p PID`.
  - Environment: no bare `env`, `printenv`, `export` or `set` (they print `SOPS_AGE_KEY`); name the variable you need.
  - Vault: no `rbw ... --json/--raw` without a `jq` field selection; prefer the redacted `rbw` MCP. Never `source` an env file to test it.
  - Diffs: `git diff`/`git show` on SOPS files decrypt through textconv; add `--no-textconv`. `ansible --diff` prints rendered credential templates.
  - CLIs: `openstack ... --long` (use `-c` columns), `set -x`/`bash -x` around anything that handles secrets, and `browser_snapshot` while a login form is open (fill with `browser_fill_secret`, then screenshot nothing).
  - Logs: `journalctl -u nginx`, access logs and debug logs hold URL tokens; filter with `grep -v 'token='` or `cut -d'?' -f1`, and never print a whole log.
  - Claude Code enforces the Bash cases with a PreToolUse hook (`claude-secret-guard`) and masks MCP results with a PostToolUse hook (`claude-secret-scan`). Codex has neither: follow this list yourself. If a command is blocked, use the suggested safe form; do not work around the hook.
- Not a credential, so no row needed: public SSH host-key fingerprints, SSH-derived age recipients (`age1...`), GPG key IDs and fingerprints, and SOPS ciphertext. `just deploy` and `gpg::auto-unlock` already mask them; if you still see one, carry on and do not log it. Everything else that authorizes access or identifies a person or device (tokens, passwords, seeds, signed URLs, webhook IDs, serials, MACs, IEEE addresses) still counts.
- If a credential (password, token, API key, private key, passkey, session cookie, ...) ends up somewhere it should not be, even briefly and even if you caused it, handle it **as soon as you notice**:
  1. Tell the user plainly what was exposed and where, naming the credential (entry or key path), never its value.
  2. Add a row under *Open* in the Obsidian note `homelab/🚨 Leaked credentials.md` (vault `/home/pschmitt/Documents/notes`; use the `obsidian` skill, or edit the file directly when the MCP cannot reach the vault): date, what, where it leaked, how to rotate, status. Never write the value into the note.
  3. Contain what you can: revoke sessions and tokens you created, shred temporary files. Rotate the credential yourself only when that can be done without the value passing through your context (see `just sops-rotate` and the credential rotation note); otherwise leave it open for the user.
  4. When something is rotated and verified, move its row to *Resolved*.

## Browser MCPs

- There is one browser MCP, `browser-daemon`. Without a choice it gives you a fresh throwaway browser on the node with the most room. `browser_status` lists the nodes and the profiles you may open; `browser_use` switches (and closes the current browser): `browser_use profile=work` for work web UIs (Outlook, OpsGenie), the persistent browser-daemon profile that is usually still signed in; `browser_use node=fnuc` for a throwaway browser on a given node (fnuc has the home IP).
- The `browser-daemon` MCP tells the browser-daemon dashboard which agent and conversation drive a session. When you start using it, label your sessions with what you are doing, a few words like a tmux window name: `browser-agent-topic "netbox invoice lookup"`. Run it again when the task changes.
- Never read a cookie or token through a browser tool; use `browser_fetch`/`browser_export_auth` (`browser-login` skill).
- Never type a password, token or TOTP code with `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`: the `browser-daemon` MCP echoes every call into the transcript and its logs. For a vault entry the user allowed for agents, use `browser_fill_secret entry="<rbw entry>" field=password|username|totp target=<ref>` (`submit=true` presses Enter): it reads the value from rbw itself, only types it on a site the entry is saved for, and masks it in later results. Its description lists the allowed entries; for anything else, have the user type it in the live view (`browser_ask_human`; `browser-login` skill). Never run `rbw get` on an entry just to type it: without a password it prints the notes.
- Look at or manage browser sessions from the shell with `browser-daemon session list|show|new|stop|rename|tabs|open`, and the same for `profile`, `recording` and `node` (`--json` for scripts, `--url` for another node, `browser-daemon tui` for a terminal UI). Only stop sessions you started: others belong to other agents.

## Shell work

- Do not duplicate shell style rules here.
- For shell scripts, shell snippets, and zsh plugin work, use the `shell` skill as the source of truth.

## Tmux pane and window naming

- At the start of each task, check `$TMUX_PANE` first. When it is set, use a bounded pane-specific query such as `tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index} #{window_name}'` to confirm the pane and identify its window. When it is unset, check whether tmux is reachable with a bounded query such as `tmux list-sessions`; tool shells may not inherit tmux variables. If tmux is unavailable, skip naming.
- As soon as the user's request makes the task clear, rename only this agent's own tmux window to a concise name for the task, before doing other task work. Use `$TMUX_PANE` as the explicit target when available. Otherwise, use discovered pane metadata and match the conversation's working directory and command where possible. Do not guess from whichever window is active.
- For a request to rename all windows or another broader scope, use the `tmux-window-names` skill and follow its discovery and verification steps.
- Use the tmux MCP tools `rename-pane` and `rename-window` (always loaded in Claude; a SessionStart hook already sets a placeholder name from the project directory, so replace it with a topic name once known).
- **Do not target tmux's "active" pane/window** when the requested target can be identified explicitly. Active means whichever window the user currently has focused, which may differ from the one this agent is using.
- Keep an existing name only when it accurately describes this agent's current work. If the user asks to rename all windows, follow the `tmux-window-names` skill.
- Keep names short: max 20 characters, no spaces — use `-` as separator.
- Examples: `nix-ai-context`, `ha-lights`, `netbox-sync`, `ctx-tmux-rename`, `ha-fints-fix-reauth`
- Do this once per conversation, as soon as the topic is clear — do not repeat.
