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
  version = "0.32.0-unstable-2026-11-24";

  src = fetchFromGitHub {
    owner = "m0nkmaster";
    repo = "msteams-mcp";
    rev = "4060d7014b87d92d9238d823ed48fcd155fe766e";
    hash = "sha256-fQ+ofEAmMScSYlYbuN1X4dgDmvWTNWyLK06e2cO8H6w=";
  };

  npmDepsHash = "sha256-f/VZrW8I/mFUCTjalkgRiwlHjot3UvWBRIPjgFEn/C0=";

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
