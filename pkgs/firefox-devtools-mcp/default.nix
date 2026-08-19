{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  geckodriver,
}:

buildNpmPackage (finalAttrs: {
  pname = "firefox-devtools-mcp";
  version = "0.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@mozilla/firefox-devtools-mcp/-/firefox-devtools-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-4YuzOVGnFLMwKpRYc4w67kCjZVz4E8asFyNq/4ETvmc=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-MCEaK6nZ1Jp8fYvvSep4BHflx7l5HLxR9I5EV8bilZk=";

  # The bundled `geckodriver` npm dependency otherwise tries to download a
  # prebuilt geckodriver binary from GitHub during `npm ci`, which the build
  # sandbox has no network access for.
  env.GECKODRIVER_SKIP_DOWNLOAD = "true";

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # Point the bundled `geckodriver` npm dependency at nixpkgs' geckodriver
  # instead of the (skipped) download, so `--connect-existing` etc. work.
  postInstall = ''
    wrapProgram $out/bin/firefox-devtools-mcp \
      --set-default GECKODRIVER_FILEPATH "${lib.getExe geckodriver}"
  '';

  meta = {
    description = "MCP server exposing Firefox DevTools (via the Firefox Remote Protocol) to AI assistants";
    homepage = "https://github.com/mozilla/firefox-devtools-mcp";
    license = with lib.licenses; [
      mit
      asl20
    ];
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "firefox-devtools-mcp";
  };
})
