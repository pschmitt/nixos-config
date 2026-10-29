{
  lib,
  buildNpmPackage,
  chromium,
  fetchFromGitHub,
}:

buildNpmPackage {
  pname = "msteams-mcp";
  version = "0.30.2-unstable-2026-10-14";

  src = fetchFromGitHub {
    owner = "m0nkmaster";
    repo = "msteams-mcp";
    rev = "cb0a1655a1dae98d7a01cfc3f68312b8b3a5bb3d";
    hash = "sha256-FdUhWfh6EnXZpzzHsjowaPQc1zAqE/snX0Xog0CvVcA=";
  };

  npmDepsHash = "sha256-3bUI5ZVeQY3A2BzrEKISKiKynVAMQd9M0RsXoHOx4Ho=";

  patches = [
    # TEAMS_MCP_BROWSER_PATH selects the browser binary instead of the
    # system Chrome/Edge channel
    ./browser-executable-path.patch
    # teams_import_session: sign in with the export of a signed-in browser
    # (browser-daemon browser_export_auth) instead of opening a login browser
    ./import-session-tool.patch
  ];

  makeWrapperArgs = [
    "--set-default"
    "TEAMS_MCP_BROWSER_PATH"
    (lib.getExe chromium)
  ];

  meta = {
    description = "Microsoft Teams MCP server using a browser session";
    homepage = "https://github.com/m0nkmaster/msteams-mcp";
    license = lib.licenses.mit;
    mainProgram = "msteams-mcp";
  };
}
