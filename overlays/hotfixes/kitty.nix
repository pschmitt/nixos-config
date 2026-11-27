{ prev }:
{
  # kitty 0.51.1 segfaults (SI_KERNEL in update_ime_position) when a key event
  # flushes a pending click that opens an overlay window, e.g. clicking a
  # remote file:// hyperlink launches the remote_file kitten. on_key_input()
  # keeps using the Window pointer it fetched before dispatching the click,
  # after the window array may have been reallocated. Re-fetch it.
  # Local fix, not yet reported upstream; kitty master still has the bug.
  # Remove once upstream on_key_input() re-fetches the window after
  # send_pending_click_to_window().
  # Last reviewed 2026-11-27 against nixpkgs-master 03b2862e40f53fe61736bb1e7df9099102354e66.
  kitty = prev.kitty.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/kitty/kitty-key-input-stale-window.patch ];
  });
}
