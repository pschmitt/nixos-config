{ prev }:
{
  # tmux 3.8 pins status drags to their starting tab, so window tabs cannot
  # be reordered. Backport upstream commit 3e9f49f, which targets the current
  # pointer position and keeps status drags out of pane bindings.
  # Remove when nixpkgs includes https://github.com/tmux/tmux/commit/3e9f49f.
  # Last reviewed 2026-11-23 against nixpkgs 04906337b6d53e8bb0eaf0470ae9f070a4d4eb55.
  tmux = prev.tmux.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/tmux/status-drag-targeting.patch ];
  });
}
