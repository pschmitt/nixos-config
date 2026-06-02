{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tmux-mcp-rs";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "bnomei";
    repo = "tmux-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-s4LiTjgdDUUzpTlql+ajydYb7Psg/G04fKjaGeBoGlY=";
  };

  cargoHash = "sha256-SFsYPyzeMlrIvulZjuXudHOF5qcf1M39W1ZZvkqgvYg=";

  meta = {
    description = "MCP server for tmux — lets AI assistants create sessions, split panes, run commands, and capture output";
    homepage = "https://github.com/bnomei/tmux-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tmux-mcp-rs";
  };
})
