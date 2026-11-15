{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_26,
}:

buildNpmPackage {
  pname = "tasker-mcp";
  version = "0.1.7-unstable-2026-11-09";
  src = fetchFromGitHub {
    owner = "pmaxhogan";
    repo = "tasker-mcp";
    rev = "6fbe63c8d92d83b2a217c56db2397b9587a62eed";
    hash = "sha256-RIcoRJcpJ2/WK9mDPDSu7djTqJZhQdL7ZAQqTrdbb5w=";
  };
  npmDepsHash = "sha256-zGOabsVbolWkEsUCEatxRQ6yVoAO3lbUSTwT9+/g4tI=";
  nodejs = nodejs_26;
  meta = {
    description = "MCP server for Tasker on Android";
    homepage = "https://github.com/pmaxhogan/tasker-mcp";
    license = lib.licenses.mit;
    mainProgram = "tasker-mcp";
  };
}
