# Repository AI Context

Use this file as lightweight shared context for AI tooling in this repository.

## General rules

- Read `AGENTS.md` and follow it as the primary repository instruction source.
- Prefer repository skills when a task matches one:
  - `shell` for bash, `sh`, and zsh
  - `nix` for NixOS and Home Manager work
  - `signal-notify` before sending any Signal message, `leaked-credentials` the moment a credential is exposed, `browser-daemon` before browser work, `browser-login` for any login in a browser session, `tmux-window-names` for renaming several tmux windows
  - `brkn-infra` to learn which host does what (build, test and deploy targets, Android devices) before you name or pick a host, `release` for releasing rbw, browser-daemon, bruvtab or monarch, `extension-dev` for browser extension work, `skill-suggestions` to review past sessions and propose skills
  - `ha`, `netbox`, `jira`, `confluence`, `obsidian`, `n8n`, `zpl`, and other repo-local skills when applicable
- Watch for toil worth capturing. When you hit the same friction a second
  time, spend real effort rediscovering a procedure, or get a user correction
  that generalizes, say so at the end of the task and propose a new skill (or an
  update to an existing one) using the `self-improvement` skill. Describe what
  it would cover and ask before creating a new skill; fixing an existing one
  falls under that skill's own rules.
- Linkify references whenever a useful target is available. This applies across
  all kinds of work, including GitLab merge requests, GitHub pull requests,
  tickets, documentation, dashboards, and local files. In terminal output, use
  OSC 8 hyperlinks (`ESC ] 8 ;; URL ESC \ label ESC ] 8 ;; ESC \`) instead of
  bare URLs or IDs; in Markdown-capable output, use Markdown links.

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
  - Hooks (`agent-secret-guard`, `agent-secret-scan`) enforce the Bash cases and warn about credentials in tool results. If a command is blocked, use the suggested safe form; do not work around the hook.
- If a credential ends up somewhere it should not be, even briefly and even if you caused it, load the `leaked-credentials` skill now and follow it; do not wait for the end of the task.

## Browser MCPs

- Load the `browser-daemon` skill before the first `browser_*` call (node and profile choice, session labelling, session management).
- Never read a cookie or token through a browser tool, and never type a password, token or TOTP code with `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`: the MCP echoes every call into the transcript and logs. Load the `browser-login` skill for any login (`browser_fill_secret`, `browser_fetch`, `browser_ask_human`).

## Shell work

- Do not duplicate shell style rules here.
- For shell scripts, shell snippets, and zsh plugin work, use the `shell` skill as the source of truth.

## Tmux pane and window naming

- Once per conversation, as soon as the task is clear, rename only this agent's own tmux window to a short topic name (max 20 characters, no spaces, `-` as separator, e.g. `nix-ai-context`, `ha-lights`). Keep an existing name only if it already describes this work.
- Identify the window via `$TMUX_PANE` (`tmux display-message -p -t "$TMUX_PANE" ...`) and rename with the tmux MCP `rename-window`. Never target the "active" window: that is whatever the user has focused. If `$TMUX_PANE` is unset, check reachability with `tmux list-sessions`; if tmux is unavailable, skip naming.
- For renaming all windows or another broad scope, use the `tmux-window-names` skill.
