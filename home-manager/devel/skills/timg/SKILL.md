---
name: timg
description: Display image files in the terminal with timg, including in a tmux floating popup.
---

# Display images with timg

Use this skill when an image needs to be viewed from an agent terminal, such as a screenshot or generated artifact.

The configured `timg` wrapper defaults to the Kitty graphics backend (`-pk`). In tmux, high-resolution Kitty output requires a Kitty-compatible outer terminal and tmux 3.3 or newer. If the outer terminal does not support Kitty graphics, use `-pq` for a quarter-block fallback. Use timg directly for inline display:

```sh
timg /absolute/path/to/image.png
```

For a static contact sheet, use `timg --grid=3x2 -pk /path/to/images/*`. `timg` does not provide left/right interactive navigation. When an interactive slideshow is wanted and `kittyview` is available, use `kittyview /path/to/images/*.png`; its left/right arrow keys navigate images and it supports Kitty graphics in tmux. See the [kittyview usage and keybindings](https://github.com/gominimal/kittyview#slideshow).

In tmux, prefer a floating popup. Always target the pane where this agent runs so the popup belongs to that pane's current window; do not rely on the active window. Use `TMUX_PANE` when available. If it is unset, identify this agent's pane from its command and working directory, then pass that pane ID explicitly. Set the popup's starting directory explicitly when using a relative image path. For example:

```sh
tmux display-popup -t "$TMUX_PANE" -E -w 80% -h 80% -d "$PWD" \
  'timg -pk "/absolute/path/to/image.png"; printf "Press Enter to close.\\n"; read -r'
```

Use an absolute image path when the file is outside the agent pane's working directory. `-d` sets the popup's working directory. `-E` closes the popup when its command finishes, so the `read` leaves time to inspect the image.

Termux should use timg's Sixel backend (`-ps`). Sixel does not work through standard tmux, so selecting the backend for an attached Termux client needs client-aware detection. Inspect tmux client metadata, potentially including dimensions, rather than assuming the agent process environment identifies the outer terminal; do not infer protocol support from screen dimensions alone. Keep this detection as follow-up work for now.
