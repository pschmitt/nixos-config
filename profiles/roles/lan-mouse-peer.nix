# lan-mouse-peer — shared lan-mouse defaults for hosts that share a
# mouse/keyboard over the LAN (currently ge2 and gk4). Each host still sets
# its own `services.lan-mouse.peers` in hosts/<host>/default.nix.
{
  services.lan-mouse = {
    enable = true;
    # More annoying than useful day-to-day -- deployed but not
    # auto-started; `systemctl --user start lan-mouse.service` when needed.
    autoStart = false;
  };
}
