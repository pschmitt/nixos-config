{
  lib,
  buildNpmPackage,
  chromium,
  fetchFromGitHub,
  python3,
  browser-daemon-client,
  teams-auth-source,
}:

buildNpmPackage {
  pname = "msteams-mcp";
  version = "0.30.3-unstable-2026-11-06";

  src = fetchFromGitHub {
    owner = "m0nkmaster";
    repo = "msteams-mcp";
    rev = "b87053a13eae91318b6c13671988c43b3bcd8548";
    hash = "sha256-7NoEJ2q1HmU9pEQxw43YayuWLypL7ATFCNtQBwBbBzk=";
  };

  npmDepsHash = "sha256-Z50P+Rln1TwTBWJQ+BBuGLf+wlpH68wumueghse9SWg=";

  patches = [
    # TEAMS_MCP_BROWSER_PATH selects the browser binary instead of the
    # system Chrome/Edge channel
    ./browser-executable-path.patch
    # session and browser profile in $XDG_STATE_HOME, token cache in
    # $XDG_CACHE_HOME, instead of ~/.teams-mcp-server
    ./xdg-directories.patch
    # sign in with the Teams login of a browser-daemon profile (see
    # TEAMS_MCP_BROWSER_DAEMON_URL) before opening a local browser
    ./browser-daemon-login.patch
    # stamp formatVariant: TEAMS, empty cards/links/files property arrays, and contenttype: Text
    ./teams-message-properties.patch
  ];

  postInstall = ''
    cp ${teams-auth-source}/custom_components/msteams/browser_auth.mjs "$out/lib/node_modules/msteams-mcp/dist/auth/browser-daemon.js"
    substituteInPlace "$out/lib/node_modules/msteams-mcp/dist/auth/browser-daemon.js" \
      --replace-fail '@TEAMS_AUTH_PYTHON@' '${
        lib.getExe (python3.withPackages (_: [ browser-daemon-client ]))
      }' \
      --replace-fail '@TEAMS_AUTH_PATH@' '${teams-auth-source}/custom_components/msteams/browser_auth.py'
  '';

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
