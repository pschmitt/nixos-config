---
name: readme
description: Use when writing, restructuring or editing a README.md (or the docs index it points to) in one of our own projects, such as rbw, browser-daemon, bruvtab or monarch. Gives the layout, what belongs in the README and what goes to docs/, and the style rules.
---

# README

Derived from the READMEs of `rbw` and `browser-daemon`. They are the reference: when in
doubt, open one and copy its shape. A README is the front door. It says what the project is,
how to install it, how to try it and where the rest lives. It is not the manual.

## Rule one: short and on point

A README is kept short and on point. Anything longer than a pitch, a list or a quick start
lives in `docs/<topic>.md`, and the main README links to it (a bullet link and a row in the
Documentation table). When you add content, first ask whether it fits in a sentence or two. If
not, it is a doc: create the file, link it from the README, and leave only a summary line behind.
Never grow the README to hold a manual.

## Layout

In this order. Drop a section only if it has nothing to say.

1. **Header block** (HTML, centred): logo (`assets/…`, with `width` and `alt`), then a badge row
   (nixbot, plus HACS or similar only if it applies), then `<h1 align="center">name</h1>`, then a
   centred one- or two-sentence tagline. For a dashboard-like project, a `<picture>` with a dark
   and a light screenshot follows.
2. **Pitch** (optional, rbw style): 2-4 sentences on the problem and how this project differs,
   placed between the header and Features. Skip it when the tagline is enough.
3. **`## Features`**: a bullet list, each bullet starts with a **bold noun phrase** and then one
   sentence. Link to the doc for the feature when there is one (for example "See `docs/mcp.md`").
4. **`## Install`**: the shortest working path first (`cargo install`, or flake input plus
   `enable = true`). Everything else (release verification, Nix details, other platforms) is a
   one-line link to `docs/install.md` or `docs/nix.md`.
5. **`## Quick start`**: one code block that shows the tool working, 5-10 lines, with a short
   trailing comment per line. Add one sentence after it for what to do next.
6. **`## Documentation`**: a two-column table, `Topic | (description)`, one row per file in
   `docs/`, in the order a reader needs them. Include the subproject READMEs
   (`browser/README.md`, `custom_components/…/README.md`) and the changelog.
7. **`## License`**: SPDX name and a link to `LICENSE`. Mention exceptions (parts under another
   license than the rest) here or in `AGENTS.md`.

## What goes where

- The README stays around 100 lines. If a section grows past a screen, move it to `docs/<topic>.md`
  and leave a link and the table row behind.
- One topic per doc file, named after the topic in lowercase (`passkeys.md`, `live-view.md`). The
  table row and the doc's `# ` title use the same words.
- Options, flags and config keys belong in the docs, not in the README. The README shows only the
  commands needed for the quick start.
- Do not repeat the same text in the README and in a doc. Link.
- Subprojects (extension, HA integration) get their own README; the root README links to it.
- Release notes go in `CHANGELOG.md`, never in the README.

## Style

- Say what the thing does, in plain present tense. No marketing words ("blazing", "powerful",
  "seamless"), no "simply" or "just".
- Name the concrete things: protocols (CDP, WebDriver BiDi), formats, commands, file paths. A
  reader should learn from a Features bullet what is actually supported.
- Short sentences. Hard-wrap prose at about 80 columns; the table rows and HTML header are exempt.
- Code blocks always carry a language (`sh`, `nix`, `js`). Shell blocks show commands without a
  `$` prompt. Comments in a block are aligned in one column.
- Use relative links for files in the repo, so they work on GitHub and in a clone. Absolute URLs
  only for outside targets and badges.
- Use `-` for bullets. No emoji. No trailing whitespace.
- Describe the project as it is now. No "new", "recently", "now supports", and no history.

## Facts and privacy

- READMEs are public. No internal hostnames, IPs, device names, credentials or private
  infrastructure; use `example.com` / `you@example.com` style placeholders, as rbw does.
- Screenshots come from a throwaway demo with made-up data, never a real instance (see
  browser-daemon's `tools/screenshots/run.sh`). Light and dark variants go in a `<picture>`.
- Every command, flag, option and link in the README must exist. Before finishing, run the quick
  start commands where it is cheap, check `--help` for flags, and check every relative link
  target exists (`rg -o '\]\(([^)#h][^)]*)\)' README.md` and `ls` them).
- When a feature is added or removed in code, update its Features bullet and the Documentation
  table in the same commit.

## Editing an existing README

1. Read the whole README and the `docs/` listing first. Keep the established section order and
   voice; do not restructure on the side.
2. Make the smallest change that makes it true. A new doc file needs a row in the table; a new
   feature needs a bullet (and a doc if it needs more than one sentence).
3. If the README has outgrown the layout, say so and propose the split before doing it.
4. Check with `rg -n ' +$' README.md docs/` for trailing whitespace and verify the links as above.
