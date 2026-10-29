---
name: zpl
description: Edit local zsh plugins at ~/.config/zsh/plugins/local. Use when the user wants to add, modify, or debug personal zsh functions, aliases, or plugin files.
---

# Local Zsh Plugins (zpl)

Plugin root: `~/.config/zsh/plugins/local`

Hermes Agent has no access to this tree: work there only on a checkout the
user provides in its workspace, without the paths or reload commands below.

## Structure

```
plugins/local/
  <topic>.zsh       # one file per topic (bat, cd, docker, http, …)
  work/             # work-specific plugins
  99-after/         # alias files that load after everything else
```

Files are sourced automatically by zinit on shell startup — no registration step needed. New `.zsh` files dropped in the root or subdirectories are picked up on the next shell start (or `source`).

## Autoloaded functions

Many plugins register a topic with `zsh::autoload-dir <topic>`. Functions for that topic live in `$ZSH_FUNCTIONS_DIR/<topic>/`,
normally `~/.config/zsh/functions/<topic>/`, with one file per function named exactly after the function. Each file contains the
function body only, without a `name() { ... }` wrapper. Plugin files keep guards, aliases, completions, and setup, and register
the topic after any capability guards.

When adding a function to an autoloaded topic, edit or create its function file rather than defining it in the plugin file. Keep
the plugin file's loader registration only when the topic is new or not already registered.

## Naming conventions

- Functions use `namespace::verb` style, e.g. `http::serve`, `files::delete-sync-artifacts`
- Aliases are defined directly (no namespace required)
- Guard capability checks with `(( $+commands[tool] )) || return`

## Code style

Follow the `shell` skill for baseline shell conventions. ZPL-specific additions:
- 2-space indentation
- `[[` not `[`
- `then` / `do` on their own line
- No `true`/`false` booleans — use `1` / unset
- Vim modeline at the bottom: `# vim: set ft=zsh et ts=2 sw=2 :`
- Use `zparseopts` for argument parsing — not `getopts`, not manual `while` loops
- Every function that accepts arguments **must** support `-h`/`--help`; print usage to stdout for `--help` and to stderr for invalid arguments (as in the `shell` skill)

## Output functions (echo.zsh)

Always use these instead of bare `echo` or `print`. All write to stderr.

| Function | Colour | Prefix | When to use |
|---|---|---|---|
| `echo::error` | red | `ERR` | fatal/unexpected errors |
| `echo::warning` | yellow | `WRN` | non-fatal issues |
| `echo::info` | blue | `INF` | general status messages |
| `echo::success` | green | `OK` | operation succeeded |
| `echo::pending` | teal | `PND` | operation in progress |
| `echo::debug` | magenta | `DBG` | verbose/debug output |
| `echo::dryrun` | cyan | `DRY` | dry-run mode messages |
| `echo::done` | green | `OK` | shorthand for `echo::success "Done!"` |
| `echo::confirm` | — | — | interactive yes/no prompt |

`echo::debug` is suppressed unless `$DEBUG` is set or `$ECHO_LEVEL` allows it.
Pass `--debug-only` / `-d` to make a message only appear when `$DEBUG=1`.

`fancify <cmd>` wraps a command showing pending → success/error output inline.

Aliases exist for convenience: `echo::err`, `echo::warn`, `echo::ok`, `echo::i`, `echo::d`, `echo::p` and the `echo_*` variants (e.g. `echo_error`).

## Tabular output

Use `tsvtool` (on `PATH`) to render tables — never implement column
alignment by hand. Emit TSV to stdout and pipe through `tsvtool pretty`:

```zsh
# basic table
{
  printf "Name\tStatus\n"
  printf "%s\t%s\n" "$name" "$status"
} | tsvtool pretty

# useful flags
tsvtool pretty -z          # zebra striping
tsvtool pretty -H          # no header row
tsvtool pretty -e "none"   # custom empty message
tsvtool header Field1 Field2  # print a bold header line standalone
```

`tsvtool pretty` auto-detects TSV, JSON, YAML, and TOML input. Use
`-o tsv/json/yaml/toml` to convert between formats.

## Colorizing output

For human-facing output, use `$fg[color]` / `$fg_bold[color]` and
`$reset_color` (zsh color variables from `colors`). Prefer the `echo::*`
functions above over manual ANSI codes — they handle color, emoji, and level
filtering automatically.

## Workflow

- This directory is managed by **yadm**, not git. Stage/commit with `yadm add`,
  `yadm commit`, etc.
- Edit files directly with standard file tools — no build step
- For plugin file changes, source `~/.config/zsh/plugins/local/<file>.zsh` or reload the full plugin set with `exec zsh`.
- For autoload function changes, use `zsh::reload-file ~/.config/zsh/functions/<topic>/<function-name>` in an interactive shell, or
  restart the shell with `exec zsh`.
