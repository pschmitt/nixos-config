{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication {
  pname = "bichon-mcp";
  version = "0.1.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "pras-labs";
    repo = "bichon-mcp";
    rev = "5f88daea7c2cfd9ee7a2d762522c33b0e6eb1dd5";
    hash = "sha256-kgNUK/AtIfYMoWlQ8B4oyWtkxHETQdCyS1Z6wJMgQkA=";
  };

  # nixpkgs ships mcp 2.x, which renamed FastMCP to MCPServer.
  postPatch = ''
    substituteInPlace bichon_mcp/server.py \
      --replace-fail "from mcp.server.fastmcp import FastMCP" \
                     "from mcp.server.mcpserver import MCPServer" \
      --replace-fail 'FastMCP("bichon-email")' 'MCPServer("bichon-email")'
  '';

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    html2text
    httpx
    mcp
  ];

  # html2text is pinned to an exact release upstream; nixpkgs ships another.
  pythonRelaxDeps = [ "html2text" ];

  pythonImportsCheck = [ "bichon_mcp" ];

  meta = {
    description = "MCP server for searching and reading emails archived by Bichon";
    homepage = "https://github.com/pras-labs/bichon-mcp";
    license = lib.licenses.agpl3Only;
    mainProgram = "bichon-mcp";
  };
}
