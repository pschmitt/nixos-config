---
name: obsidian
description: Read and write Obsidian vault notes at ~/Documents/notes via the filesystem MCP server. Use when the user wants to create, search, update, or organize notes, diary entries, or any markdown files in the vault.
---

# Obsidian Vault

MCP server name: `obsidian`
Vault root: `/home/pschmitt/Documents/notes`

## Key tools

- `list_directory` / `directory_tree` — explore vault structure
- `search_files` — find notes by filename pattern
- `read_file` / `read_multiple_files` — read note content
- `write_file` — create or overwrite a note
- `edit_file` — make targeted edits to existing notes
- `move_file` — rename or reorganize notes

## Vault structure

```
notes/
  diary/          # daily notes, named YYYY-MM-DD.md
  projects/       # project notes
  homelab/        # self-hosting and infrastructure
  home-assistant/ # HA-related notes
  devices/        # hardware notes
  health/         # health tracking
  tech/           # general tech notes
  linux/          # Linux tips and references
  scripts/        # script snippets
  shopping/       # purchase research
  archive/        # old/inactive notes
  attachments/    # binary attachments
  _assets/        # vault assets
```

## Conventions

- Plain markdown, no required frontmatter
- Diary entries: `diary/YYYY-MM-DD.md`, one file per day
- Use `[[wikilink]]` syntax for internal links
- Headings with `#` to structure content within a note
- Prefer flat filenames inside topic directories over deep nesting
