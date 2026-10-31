{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  pnpmConfigHook,
  fetchPnpmDeps,
  makeWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "concord-mcp";
  # renovate: datasource=github-releases depName=Get-Concord-AI/concord-mcp
  version = "0.19.0";

  src = fetchFromGitHub {
    owner = "Get-Concord-AI";
    repo = "concord-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ocI6BbYxJinZOiY4MSjZmWnT4o2bLVWBqJxZ5AkFP3k=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-11CS5x7DwB9gZokhlKNGmgTnFJIxz1+Ajgp//j0Y1x8=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs_22
    pnpm_10
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/concord-mcp
    cp -r dist plugin package.json $out/lib/concord-mcp/

    # Production dependencies only
    pnpm prune --prod --ignore-scripts
    cp -r node_modules $out/lib/concord-mcp/

    makeWrapper ${lib.getExe nodejs_22} $out/bin/concord-mcp \
      --add-flags $out/lib/concord-mcp/dist/index.js
    makeWrapper ${lib.getExe nodejs_22} $out/bin/concord \
      --add-flags $out/lib/concord-mcp/dist/cli/index.js

    runHook postInstall
  '';

  meta = {
    description = "Cross-harness messaging and shared work-state for coding agents through MCP";
    homepage = "https://github.com/Get-Concord-AI/concord-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "concord";
  };
})
