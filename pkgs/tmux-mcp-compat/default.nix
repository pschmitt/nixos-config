{ writers }:

# tmux-mcp-rs aborts when a client opens with `server/discover` (codex, agy);
# this proxy rejects that request so the client falls back to `initialize`.
writers.writePython3Bin "tmux-mcp-compat" {
  flakeIgnore = [
    "E501"
    "W503"
  ];
} (builtins.readFile ./scripts/tmux-mcp-compat.py)
