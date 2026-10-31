---
name: terminal-browser-headless
description: Use instead of the upstream terminal-browser skill when running as an agent on fnuc (no graphical terminal). Opens and drives terminal-browser through a headless kitty so `open` and `action` work from an agent shell.
---

# terminal-browser on fnuc

Bare `terminal-browser open` fails in an agent shell (no kitty, no graphics, no
tty). fnuc runs a headless weston and kitty as user services
(`terminal-browser-weston`, `terminal-browser-kitty`); use the
`terminal-browser-headless` wrapper, which starts them on demand.

- Open: `terminal-browser-headless open URL|FILE`
- List: `terminal-browser-headless ls --all` (plain `ls` only shows browsers of
  the current terminal tab, which is none here). The first column is the browser KEY.
- Drive: `terminal-browser-headless action --browser KEY -- snapshot`
  (also `click @e14`, `fill @e3 "text"`, `eval "document.title"`; see the
  upstream `terminal-browser` skill for the command set).

Always pass `--browser KEY` to `action`; without it the command looks for a
browser in the current terminal tab and finds none. Nothing is shown to the
user: this is for reading and driving pages, not for screenshots to the human
(use browser-daemon or an artifact for that).
