{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tmux-mcp-rs";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "bnomei";
    repo = "tmux-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-YT0yvTC2iM2j0ckEP+7PfLNjRJmP9Dt7T0P/Ufp2Wv4=";
  };

  cargoHash = "sha256-MZV/yuTMOdsOQqjdNflaIJSJzgQ3KXAo5xgnesmltoE=";

  meta = {
    description = "MCP server for tmux — lets AI assistants create sessions, split panes, run commands, and capture output";
    homepage = "https://github.com/bnomei/tmux-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tmux-mcp-rs";
  };
})
