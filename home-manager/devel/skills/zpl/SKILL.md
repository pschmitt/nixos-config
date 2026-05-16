---
name: zpl
description: Edit local zsh plugins at ~/.config/zsh/plugins/local. Use when the user wants to add, modify, or debug personal zsh functions, aliases, or plugin files.
---

# Local Zsh Plugins (zpl)

Plugin root: `~/.config/zsh/plugins/local`

## Structure

```
plugins/local/
  <topic>.zsh       # one file per topic, ~264 files (bat, cd, docker, http, …)
  work/             # work-specific plugins (~47 files)
  99-after/         # alias files that load after everything else (~12 files)
```

Files are sourced automatically by zinit on shell startup — no registration step needed. New `.zsh` files dropped in the root or subdirectories are picked up on the next shell start (or `source`).

## Naming conventions

- Functions use `namespace::verb` style, e.g. `http::serve`, `files::delete-sync-artifacts`
- Aliases are defined directly (no namespace required)
- Guard capability checks with `(( $+commands[tool] )) || return`

## Code style

Follow the repo shell style (see CODESTYLE.md):
- 2-space indentation
- `[[` not `[`
- `then` / `do` on their own line
- No `true`/`false` booleans — use `1` / unset
- Vim modeline at the bottom: `# vim: set ft=zsh et ts=2 sw=2 :`
- Use `zparseopts` for argument parsing — not `getopts`, not manual `while` loops
- Every function that accepts arguments **must** support `-h`/`--help` and print usage to stderr

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

## Workflow

- Edit files directly with standard file tools — no build step
- Test immediately: `source ~/.config/zsh/plugins/local/<file>.zsh`
- Or reload the full plugin set: `exec zsh`
