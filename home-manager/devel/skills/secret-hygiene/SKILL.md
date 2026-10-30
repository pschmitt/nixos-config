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

## Hooks

`agent-secret-guard` enforces the Bash cases and `agent-secret-scan` warns about credentials in tool results. If a command is blocked, use the suggested safe form; do not work around the hook.

## If it leaks anyway

Load the `leaked-credentials` skill now. When it asks for a prevention fix, add the missing command or habit to the list above.
