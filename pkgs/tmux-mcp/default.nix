{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tmux-mcp-rs";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "bnomei";
    repo = "tmux-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Umnh1YXPonbtnlQyJex9tuVXJVIeGRd/FVHMUxiDk1s=";
  };

  cargoHash = "sha256-YiEstaMUNwuaRR3bTjjQ2Ew/txhwNoa0POfhplYUkhI=";

  meta = {
    description = "MCP server for tmux — lets AI assistants create sessions, split panes, run commands, and capture output";
    homepage = "https://github.com/bnomei/tmux-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tmux-mcp-rs";
  };
})
