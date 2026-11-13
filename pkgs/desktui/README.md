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
this conflicts with tmux's own prefix.

## tmux

The outer terminal must support Kitty graphics. Enable passthrough in tmux:

```tmux
set -g allow-passthrough on
```

The patch detects `$TMUX` and wraps each Kitty graphics APC in its own tmux DCS
envelope, doubling embedded escape bytes. Regular text, cursor positioning,
geometry queries and input-mode negotiation remain pane-local. Graphics probes,
frame chunks and image deletion during teardown all use the same transport.
The final probe sentinel also passes through tmux so the outer graphics reply
arrives before capability collection ends.

An image lands where the *outer* terminal's cursor is, which tmux does not track.
The cursor address that precedes each placement therefore travels inside the same
envelope, shifted by the pane's position in the client (`pane_left`, `pane_top`
and a top status line, re-read about once a second), between a cursor save and
restore so tmux's own idea of the cursor stays true.

tmux never relays the outer terminal's reply to the graphics probe, so detection
inside tmux always fails; pass `--force` there (the OpenStack bridge does).

Shared-memory graphics are disabled under tmux: the server and attached terminal
may be on different machines. Direct transfer works across SSH as well.

Start in a zoomed pane. Passthrough does not give tmux ownership of graphics;
arbitrary split-pane placement, window switching, nested tmux sessions and
multiple attached clients are not guaranteed by this patch.

## Checks

```sh
nix build '.#desktui'
nix build '.#desktui.tests.tmux'
```

Run builds on a worker as required by the repository guidelines. The package runs
upstream Rust tests, including byte-level transport regressions. The separate
tmux check creates an isolated server attached to a pseudo-terminal that emulates
Kitty graphics replies. It checks capability discovery without `--force`, decodes
RGB tiles from the synthetic test pattern after they pass through tmux, and
checks clean exit using the local command prefix. It needs no cloud credentials
and sends no input to a VM. This validates protocol transport, not a human visual
inspection in a real graphical terminal.

## OpenStack

This client speaks TCP VNC, not OpenStack's noVNC WebSocket transport. A
WebSocket-to-loopback-TCP bridge is still required. Keep console URLs and their
encoded query parameters out of logs and command output; do not store console
tokens in the package or its tests.
