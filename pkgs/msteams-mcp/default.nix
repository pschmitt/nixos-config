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

  postPatch = ''
    substituteInPlace src/browser/context.ts \
      --replace-fail '      channel,' '      executablePath: "${lib.getExe chromium}",'
  '';

  meta = {
    description = "Microsoft Teams MCP server using a browser session";
    homepage = "https://github.com/m0nkmaster/msteams-mcp";
    license = lib.licenses.mit;
    mainProgram = "msteams-mcp";
  };
}
