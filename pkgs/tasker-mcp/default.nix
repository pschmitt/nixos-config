{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_26,
}:

buildNpmPackage {
  pname = "tasker-mcp";
  version = "0.1.1-unstable-2026-11-16";
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "tasker-mcp";
    rev = "ca310d5e6b1502f3920cfb01abb61ca6b3362513";
    hash = "sha256-XQl1ST+X+z5CVACa89nNBD4JXsfu45yguHSJ8dZWQ9Y=";
  };
  npmDepsHash = "sha256-zGOabsVbolWkEsUCEatxRQ6yVoAO3lbUSTwT9+/g4tI=";
  nodejs = nodejs_26;
  meta = {
    description = "MCP server for Tasker on Android (pschmitt fork: persist without the screen, XDG dirs)";
    homepage = "https://github.com/pschmitt/tasker-mcp";
    license = lib.licenses.mit;
    mainProgram = "tasker-mcp";
  };
}
