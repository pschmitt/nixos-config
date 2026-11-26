---
name: zpl
description: Edit local zsh plugins at ~/.config/zsh/plugins/local. Use when the user wants to add, modify, or debug personal zsh functions, aliases, or plugin files.
---

# Local Zsh Plugins (zpl)

Installed at `~/.config/zsh/plugins/local` (functions in
`~/.config/zsh/functions`) as read-only Home Manager links. Edit the sources:

- public: `nixos-config.git/home-manager/cli/zsh/files/{plugins/local,functions}`
- private (work, personal, anything sensitive):
  `nixos-config-private.git/hm/zsh/files/{plugins/local,functions}`

Hermes Agent has no access to this tree: work there only on a checkout the
user provides in its workspace, without the paths or reload commands below.

## Structure

```
plugins/local/
  <topic>.zsh       # one file per topic (bat, cd, docker, http, …)
  work/             # work-specific plugins
  99-after/         # alias files that load after everything else
```

Every `.zsh` file in the root, `work/` and `99-after/` of both trees is loaded on shell startup, in that order and sorted by
name. Home Manager bundles them at build time into one zcompiled file (`~/.config/zsh/plugins/local.zsh`, built by
`home-manager/cli/zsh/files/default.nix`) in which each plugin is a function `zpl::<name>`; interactive shells run them after
the first prompt. New or changed files take effect after the next Home Manager switch (`zsrclocal` reloads the bundle in a
running shell). For an uncommitted experiment, put the code in `~/.config/zsh/static/*.zsh` instead.

Because each plugin runs as a function: `(( $+commands[tool] )) || return` skips the rest of that plugin, `typeset`/`local`
without `-g` stay local to it, and aliases are not expanded in its code (write commands out).

## Autoloaded functions

Every function file is autoloaded: functions live in `$ZSH_FUNCTIONS_DIR/<topic>/`, normally `~/.config/zsh/functions/<topic>/`,
with one file per function named exactly after the function. Each file contains the function body only, without a
`name() { ... }` wrapper. Home Manager generates the registrations for all topics, so a new topic needs no plugin file; plugin
files only hold guards, aliases, completions and setup.

When adding a function, edit or create its function file rather than defining it in the plugin file.

## Naming conventions

- Functions use `namespace::verb` style, e.g. `http::serve`, `files::delete-sync-artifacts`
- Aliases are defined directly (no namespace required)
- Guard capability checks with `(( $+commands[tool] )) || return` only for tools that some hosts have and others do not
  (NetworkManager, fprintd, ...). No guard for tools Nix installs on every host (coreutils, git, tmux, fzf, ...).
- A plugin that only makes sense on NixOS hosts (systemd, journald, bootctl, udev, nixos) has no guard either: the
  TermuxPP phones do not ship it at all through `programs.zsh.localConfig.excludeTopics`
  (`profiles/specializations/termuxpp/home.nix`), which drops `<topic>.zsh` and `functions/<topic>/`. Add a topic there
  rather than a guard. Desktop-session topics (Hyprland, Wayland, X, audio, ...) are excluded the same way on every host
  without a GUI (`home-manager/cli/zsh/files/default.nix`); `profiles/specializations/termuxpp/tests.nix` checks both.
- Short names for a whole function family (`net::` for `network::`, `k::` for `kubectl::`) are not plugin loops: add a
  `programs.zsh.localConfig.prefixAliases` entry (private: `hm/zsh/files.nix`). They are generated at build time from the
  function files and the names plugins define; a family a plugin creates at runtime (`eval` in a loop) has to add its
  short names in that loop.
- Environment for Nix-managed tools (`FZF_DEFAULT_OPTS`, ...) belongs in their Nix module
  (`home-manager/cli/zsh/fzf.nix`), not in a plugin: plugins load later and would override it.

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

- Edit the source tree in the nixos-config (or private) checkout, commit, and
  deploy with Home Manager (see AGENTS.md there); `git add -N` new files first.
- To try a change before deploying, `source` the edited source file in a shell,
  or drop a `*.zsh` override in `~/.config/zsh/static/` (loaded last).
- After a switch, reload the full plugin set with `zsrclocal` or `exec zsh`.
- For autoload function changes, use `zsh::reload-file ~/.config/zsh/functions/<topic>/<function-name>` in an interactive shell, or
  restart the shell with `exec zsh`.
- Measure with `ZSH_PLUGIN_TIMINGS=1 ZSH_SYNC_LOCAL_PLUGINS=1 zsh -i -c exit` (per-plugin ms on stderr). A plugin runs in
  every new shell: no subshells, forks or network calls at load time; cache expensive results (see
  `kubectl::context-colors`).

## Checking a change before deploying

For changes to the loader, ordering or many plugins at once, compare the full shell state of the current and the new
config without switching:

1. Build the host's `home-manager-files` on a build host (nix skill, `remote-sync.sh`), copy it back with
   `nix copy --from ssh-ng://<build-host> <path>`, then `cp -a <path>/.config/zsh ./newzsh && chmod -R u+w ./newzsh`.
2. Dump both states (`scripts/` is next to this file): `scripts/zsh-state.zsh old.txt` and
   `scripts/with-zsh-config.sh ./newzsh -- scripts/zsh-state.zsh new.txt` (bind-mounts the new tree over
   `~/.config/zsh` in a user namespace, no root needed).
3. `scripts/zsh-state-diff.py old.txt new.txt` lists changed or missing functions, aliases, key bindings, zstyles,
   options, completions and parameters. Explain every difference before committing.
4. For the interactive (deferred) path, drive `scripts/with-zsh-config.sh ./newzsh -- zsh -i` through `script -qfc` and
   check `~/.cache/zsh/local-plugins.log` stays empty.
