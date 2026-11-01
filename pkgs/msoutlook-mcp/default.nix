{
  lib,
  buildNpmPackage,
  chromium,
  fetchFromGitHub,
}:

buildNpmPackage {
  pname = "msoutlook-mcp";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "shayanline";
    repo = "msoutlook-mcp";
    rev = "79b0a2fac890007a930b74f4d5056f0952986ede";
    hash = "sha256-rUVdOYl5R1XbYZzpOZeNBbeo10sFybEiFJrAmWmi1Z8=";
  };

  npmDepsHash = "sha256-oFERRSzFxpAZs3OruFhA5UdUqZl82AIOk8zY01CP/Zs=";

  patches = [ ./browser-daemon-login.patch ];

  npmBuildScript = "build";

  makeWrapperArgs = [
    "--set-default"
    "MSOUTLOOK_BROWSER_PATH"
    (lib.getExe chromium)
  ];

  meta = {
    description = "Microsoft Outlook MCP server authenticated through browser-daemon";
    homepage = "https://github.com/shayanline/msoutlook-mcp";
    license = lib.licenses.mit;
    mainProgram = "msoutlook-mcp";
  };
}
