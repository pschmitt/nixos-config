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
  version = "0.20.0";

  src = fetchFromGitHub {
    owner = "Get-Concord-AI";
    repo = "concord-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-xGge5VUxx9MqBlF9WJHZIumtkEalmj+5kE8jxaMGDtM=";
  };

  # Concord keeps its user-level state in a hardcoded ~/.concord; move it to
  # $XDG_DATA_HOME/concord.
  #
  # `concord release <task> --reason ...` is an operator override for tasks
  # whose owning agent session is gone: the owner check blocks every agent,
  # `force` only works for a registered agent with the same human owner, and
  # claims never expire. `concord release --stale-since-boot` does it for every
  # claim nothing touched since the last boot (see home-manager/devel/concord.nix).
  # Not an MCP tool, so agents cannot call it as one.
  patches = [
    ./xdg-state-dir.patch
    ./operator-release.patch
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-Tn6wk72/rDG09gf1aZaH8NjKXAcr+BLkeBosZq2iuc8=";
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
