# Repository AI Context

Use this file as lightweight shared context for AI tooling in this repository.

## General rules

- Read `AGENTS.md` and follow it as the primary repository instruction source.
- Treat `AGENTS.md` as publishable: no credentials and no private infrastructure identifiers (hostnames, FQDNs, IPs, device names, topology). Use roles or placeholders; host details live in the private `brkn-infra` skill.
- Load the matching skill before the work it covers:
  - `rworker` before any heavy compilation, build, test suite, or Nix evaluation; `scratch-space` before creating large temp files
  - `shell` for bash, `sh`, zsh; `nix` for NixOS and Home Manager; `ci-workflows` for GitHub Actions using `pschmitt/ci-workflows`
  - `signal-notify` before any Signal message (the user may be away during long work)
  - `secret-hygiene` before commands that may print credentials; `leaked-credentials` the moment a credential is exposed
  - `browser-daemon` before the first `browser_*` call; `browser-login` for any login, passkey or CAPTCHA in a browser session
  - `git-commit` before every commit: checkouts and their git index are shared between agents, so commit only your own paths; it points to `gpg-signing` for signed commits and tags
  - `tmux-window-names`: as soon as the task is clear and whenever the topic changes, rename only this agent's own window (`$TMUX_PANE`)
  - `deploy` whenever asked to deploy: bump the flake input in nixos-config, push, roll out to the hosts, as fast as possible (never a release); `release` only to cut a version or tag
  - `brkn-infra` for host roles, build/test/deploy targets and Android devices; `extension-dev`, `skill-suggestions`
  - `timg`, `ha`, `netbox`, `jira`, `confluence`, `obsidian`, `n8n`, `zpl` and other repo-local skills when applicable
- Watch for toil worth capturing (the same friction twice, a rediscovered procedure, a generalizing user correction). Say so at the end of the task and propose a skill or skill update with the `self-improvement` skill; ask before creating a new skill.
- Linkify references (MRs, PRs, tickets, docs, dashboards, local files): OSC 8 hyperlinks in terminal output, Markdown links where Markdown renders.
- Subagents: use the harness's native subagent tool (never shell out to `codex exec` or `claude`) and a cheap model: Sonnet in Claude Code / Claude Work (never Opus), Luna in Codex, Gemini Flash in Antigravity (never Pro). `claude-auto` picks `subscription-subagent` automatically.

## Concord

- Concord MCP is available in every repository. Before editing, call `start_work` with the task and the files or modules you expect to touch; resolve reported overlaps first. Use `inspect_work`, `update_work` (progress, and `operation="prompt"` to message any active agent machine-wide), `transfer_work`, and `finish_work` with outcome, changed files and tests.
- For paired or multi-repository workflows, use the `workspace_id` designated in the repository's `AGENTS.md` (or set `CONCORD_REPO_ROOT`).
- Do not run `concord setup` yourself.

## Host awareness

- Always know which host you are on (`hostname` or `$HOST`). **Never SSH into the current host**; run commands locally instead.

## Code and validation

- Keep changes minimal and targeted. Preserve existing user changes; do not revert unrelated edits.
- Format and lint with the repo-standard tools. For Nix: `nixfmt` and `statix check` from within `nix develop`.
- Never introduce trailing whitespace.

## Command safety

- No unbounded filesystem traversals: prefer `rg --files` or a targeted `rg` over `find`/`bfs`. If you must use them, scope to the smallest directory, exclude large/generated paths and wrap in `timeout 5m`.
- Never search recursively from `/`, a home directory or `/nix/store`. If a scoped search times out, narrow it instead of rerunning it.
- Keep large files out of `/tmp` and `$XDG_RUNTIME_DIR` (often RAM-backed): put them under `${XDG_CACHE_HOME:-~/.cache}/agents/<PROJECT_NAME>/` and delete them when done.

## Secrets

- Keep secret values out of tool-call arguments, output, transcripts and chat: pass them by file, stdin or environment, and mask them when diffing or listing. Filter private Nix modules to the needed option (`rg -A`) instead of printing whole files.
- The `agent-secret-guard` and `agent-secret-scan` hooks enforce the Bash cases; if a command is blocked, use the suggested safe form and do not work around the hook.
- Never read a cookie or token through a browser tool, and never type a password, token or TOTP code with `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`; use `browser-login`.
- After a leak is contained, propose an update to the relevant skill, `CONTEXT.md`, `AGENTS.md` or hook so it cannot recur.

## Deployment and operations

- **Never run heavy compilation, builds, or Nix evaluations on the local host** (including in Codex and delegated subagents): `cargo build/check/test/clippy`, `nix build/eval/flake check`, Android/Gradle, container builds, large test suites. Offload to an ad-hoc `rworker` VM; use a shared build host only for quick one-offs.
- To deploy host changes, use `just deploy TARGET_HOST`.
- For Home Assistant CLI access, prefer `zsh -lc 'zhj hass-cli ...'`.

## Version control workflow

- Do not open pull requests unless explicitly requested. Work directly on `main` (or the default branch) without feature branches.
- Once a change is done and verified, commit it, push it to the default branch and deploy it to the affected hosts without asking. Leave unrelated modified or untracked files out of the commit.
- After pushing to `nixos-config-private`, update the public repo's `flake.lock` (`nix flake lock --update-input nixos-config-private`, on a remote build host), copy it back, and commit it as `bump my privates`.
