{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tmux-mcp-rs";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "bnomei";
    repo = "tmux-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-iB9fn6mn48f/cW/TWHIi1rhbw7eYEv5+ccMSUFljMlo=";
  };

  cargoHash = "sha256-wNzYDsk2r5O/BCOe9Zwj/PlHVUwm9JieLyX2M503hyc=";

  meta = {
    description = "MCP server for tmux — lets AI assistants create sessions, split panes, run commands, and capture output";
    homepage = "https://github.com/bnomei/tmux-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "tmux-mcp-rs";
    platforms = [ "x86_64-linux" ];
  };
})
