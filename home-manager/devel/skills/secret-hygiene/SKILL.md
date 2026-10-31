---
name: secret-hygiene
description: Keep secret values out of tool calls, tool output, transcripts and logs. Use before running commands that may print credentials (Home Assistant config, process lists, environment dumps, rbw, SOPS diffs, openstack, journalctl, browser snapshots) or when handling any password, token or key.
---

# Secret hygiene

Keep secret values out of everything you can see or log: tool-call arguments, tool output, files the tools echo back (e.g. code passed to a browser tool is repeated in its output), transcripts and chat. Pass them by file, stdin, environment or a one-shot local channel instead, and mask them when diffing or listing.

## Commands that caused past leaks

Use the safe form:

- Home Assistant: never read `.storage/core.config_entries`, `.storage/auth` or `secrets.yaml`, and never `rg`/`grep` `/mnt/ha` without `-l` or a `--glob '!...'` that excludes them. Use `zsh -lc 'zhj hass::config-entries [--domain X]'` (key names only) and `zhj hass::check-config` instead of `ha core check`. Filter `ha core logs`/`ha apps info` with `jq` or `grep -v` on named fields.
- Processes: no `ps aux`, `ps -ef`, `pgrep -a`, or `/proc/*/cmdline` (signed browser URLs, `--passwd` arguments). Use `pgrep -l NAME`, `pgrep -c NAME` or `ps -o pid,etime,comm -p PID`.
- Environment: no bare `env`, `printenv`, `export` or `set` (they print `SOPS_AGE_KEY`); name the variable you need.
- Vault: no `rbw ... --json/--raw` without a `jq` field selection; prefer the redacted `rbw` MCP. Never `source` an env file to test it.
- Diffs: `git diff`/`git show` on SOPS files decrypt through textconv; add `--no-textconv`. `ansible --diff` prints rendered credential templates.
- CLIs: `openstack ... --long` (use `-c` columns), `set -x`/`bash -x` around anything that handles secrets, and `browser_snapshot` while a login form is open (fill with `browser_fill_secret`, then screenshot nothing).
- Logs: `journalctl -u nginx`, access logs and debug logs hold URL tokens; filter with `grep -v 'token='` or `cut -d'?' -f1`, and never print a whole log.

## Filtering what reaches the provider (`claude-ogl`, `codex-ogl`)

Hooks cannot stop a secret that is already in a prompt. `claude-ogl` and `codex-ogl` run the agent behind og-local, a local proxy with an ML detector that swaps PII and secrets for placeholders before the request leaves the machine and restores them in the reply. Plain `claude` and `codex` are unaffected.

- Coverage (tested with made-up values): it catches bare passwords, YAML passwords, webhook IDs, signed URLs, GitHub tokens and personal data. It **misses** AWS keys, JWTs, private-key blocks and age keys, so the hooks and the command rules above still matter for those.
- Secretgate (regex layer, `pkgs.secretgate`) catches exactly those formats but is **off by default**: chained behind og-local, any turn that calls a tool hangs (audit mode too, HTTP/1.1 does not help). Each tool alone works. Enable with `OGL_SECRETGATE_MODE=redact|audit|block` only to test a fix.
- Cost: og-local runs the detector on the CPU, so even a one-word reply takes about 35-50 s and a few minutes of CPU. Do not run it in bulk (for example `claude mcp list` starts every MCP server at once and spiked fnuc's load).
- `codex-ogl` rebuilds Codex's home from the real one, because `ogl codex` otherwise starts Codex with a bare config; it uses `--profile ogl` because current Codex rejects ogl's legacy `profile` key.
- HTTP MCP proxies trust `SSL_CERT_FILE`, so they keep working behind a TLS-intercepting proxy.

## Hooks

`agent-secret-guard` enforces the Bash cases and `agent-secret-scan` warns about credentials in tool results. If a command is blocked, use the suggested safe form; do not work around the hook.

## If it leaks anyway

Load the `leaked-credentials` skill now. When it asks for a prevention fix, add the missing command or habit to the list above.
