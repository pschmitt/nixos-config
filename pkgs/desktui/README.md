# desktui

A VNC viewer that draws the remote framebuffer inside a Kitty-graphics-capable
terminal. This package builds upstream v0.4.0 with a tmux passthrough patch.

```sh
nix run '.#desktui' -- --print-caps
nix run '.#desktui' -- --test-pattern
nix run '.#desktui' -- 127.0.0.1::5901 --scale fit --view-only --no-clipboard
```

The double colon selects a TCP port rather than a VNC display number. The local
command prefix is **Ctrl+A**; follow it with **q** to exit. Use `--prefix` when
this conflicts with tmux's own prefix. `--no-status` hides the bottom status
line so the remote screen fills the whole terminal.

## tmux

The outer terminal must support Kitty graphics **and Unicode image placeholders**
(Kitty 0.28 or newer). Enable passthrough in tmux:

```tmux
set -g allow-passthrough on
```

The patch detects `$TMUX` and wraps each Kitty graphics APC in its own tmux DCS
envelope, doubling embedded escape bytes. Regular text, cursor positioning,
geometry queries and input-mode negotiation remain pane-local. Graphics probes,
frame chunks and image deletion during teardown all use the same transport.
The final probe sentinel also passes through tmux so the outer graphics reply
arrives before capability collection ends.

Under tmux, images use virtual placements (`U=1`), displayed through Unicode
placeholder cells. The cells remain pane-local: tmux owns their position and
visibility, so changing windows, moving panes and zooming no longer leave real
placements behind in the outer terminal. Tile updates do not delete the previous
image first, and synchronized-output boundaries reach the outer terminal along
with the image data. Partial edge tiles are padded transparently to whole cells
rather than stretched.

The viewer checks which attached clients show its window. When that set changes,
it retransmits every tile so a returning or newly attached client receives the
image data even if the guest screen has not changed. Normal tmux passthrough
policy suppresses image transfers to clients that are not viewing the pane.

tmux never relays the outer terminal's reply to the graphics probe, so detection
inside tmux always fails; pass `--force` there (the OpenStack bridge does).

Shared-memory graphics are disabled under tmux: the server and attached terminal
may be on different machines. Direct transfer works across SSH as well.

Nested tmux sessions and terminals without Unicode placeholder support are not
supported by this path. Each attached graphical client needs placeholder support.

## Checks

```sh
nix build '.#desktui'
nix build '.#desktui.tests.tmux'
```

Run builds on a worker as required by the repository guidelines. The package runs
upstream Rust tests, including byte-level transport regressions. The separate
tmux check creates an isolated server attached to a pseudo-terminal that emulates
Kitty graphics replies. It checks capability discovery without `--force`, decodes
RGBA tiles from the synthetic test pattern after they pass through tmux, verifies
virtual placements and complete retransmission after switching windows, and
checks clean exit using the local command prefix. It needs no cloud credentials
and sends no input to a VM. This validates protocol transport, not a human visual
inspection in a real graphical terminal.

## OpenStack

This client speaks TCP VNC, not OpenStack's noVNC WebSocket transport. A
WebSocket-to-loopback-TCP bridge is still required. Keep console URLs and their
encoded query parameters out of logs and command output; do not store console
tokens in the package or its tests.
