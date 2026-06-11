{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tmux-mcp-rs";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "bnomei";
    repo = "tmux-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-PYME5/FW/87QrufAM3KD4AlJCut4PSImfBVp7L5aw/g=";
  };

  cargoHash = "sha256-+XHzCGJYrIoiajQ3VkmfIeWNMCaebZT0WJ8qVKwHXkE=";

  meta = {
    description = "MCP server for tmux — lets AI assistants create sessions, split panes, run commands, and capture output";
    homepage = "https://github.com/bnomei/tmux-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tmux-mcp-rs";
  };
})
