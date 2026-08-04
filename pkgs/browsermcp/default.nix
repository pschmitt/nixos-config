{
  lib,
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage (finalAttrs: {
  pname = "browsermcp";
  version = "0.1.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/@browsermcp/mcp/-/mcp-${finalAttrs.version}.tgz";
    hash = "sha256-KtNMKRRcqAxfLn2OyQ4FiWl7GTOLK0WoPJGNSQekz5Y=";
  };

  # The published tarball's package.json still carries workspace:* devDependencies
  # from the upstream monorepo (its README says it "cannot yet be built on its
  # own"), which npm can't resolve outside that monorepo. Swap in a trimmed
  # package.json (runtime deps only, no scripts) with a matching lockfile
  # generated from it, since dist/index.js already ships prebuilt.
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-vSm6uYDuYWg/pkomGoByBWmAbQhmOJR6Axby/CoiR4s=";

  dontNpmBuild = true;

  meta = {
    description = "MCP server for browser automation via the Browser MCP Chrome extension";
    homepage = "https://browsermcp.io";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "mcp-server-browsermcp";
  };
})
