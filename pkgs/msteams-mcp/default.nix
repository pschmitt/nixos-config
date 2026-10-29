{
  lib,
  buildNpmPackage,
  chromium,
  fetchFromGitHub,
}:

buildNpmPackage {
  pname = "msteams-mcp";
  version = "0-unstable-2026-08-14";

  src = fetchFromGitHub {
    owner = "hickeroar";
    repo = "msteams-mcp";
    rev = "68d57bf65b595d3cab4478efe86987b3335709c7";
    hash = "sha256-dL2Qzj7afPCFWQYrEJSWDMY/I46XEK5KWfRVK7GZ1/4=";
  };

  npmDepsHash = "sha256-4KtuX0+e3br83EbFYPFj9MdxCzfi1CJQ3WZLH18Dfk4=";

  postPatch = ''
    substituteInPlace src/browser/context.ts \
      --replace-fail '      channel,' '      executablePath: "${lib.getExe chromium}",'
  '';

  meta = {
    description = "Microsoft Teams MCP server using a browser session";
    homepage = "https://github.com/hickeroar/msteams-mcp";
    license = lib.licenses.mit;
    mainProgram = "msteams-mcp";
  };
}
