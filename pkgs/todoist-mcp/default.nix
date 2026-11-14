{
  lib,
  stdenv,
  buildNpmPackage,
  fetchNpmDeps,
  fetchFromGitHub,
  jq,
  makeWrapper,
  nodejs,
}:

buildNpmPackage (finalAttrs: {
  pname = "todoist-mcp";
  version = "15.2.1";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = "todoist-mcp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-5g747nRkizuZwVFfEKn/D28+Yysujd8+7y9I7dYdXkQ=";
  };

  npmDepsHash = "sha256-oY8MFsQlwUXeP4qjku7MrBnu7XEenz74pl3TVj67QVc=";

  npmDeps = fetchNpmDeps {
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    hash = finalAttrs.npmDepsHash;
    inherit (finalAttrs) src;
    prePatch = finalAttrs.prePatch or "";
    patches = finalAttrs.patches or [ ];
    postPatch = finalAttrs.postPatch or "";
    patchFlags = finalAttrs.patchFlags or [ ];
    fetcherVersion = finalAttrs.npmDepsFetcherVersion or 1;
    nativeBuildInputs = [ jq ];
  };

  postPatch = ''
    jq 'del(.scripts.prepare)' package.json > package.json.new
    mv package.json.new package.json
  '';

  doCheck = false;

  preInstall = ''
    mkdir -p "$out/lib/node_modules/@doist/todoist-mcp"
  '';

  nativeBuildInputs = [ jq ] ++ lib.optionals stdenv.hostPlatform.isAarch64 [ makeWrapper ];

  # Under aarch64 QEMU, npm ci needs --jitless to avoid a QEMU JIT crash, but
  # Vite needs WebAssembly during the build. Run npm itself single-threaded and
  # clear NODE_OPTIONS for Vite; restore --jitless for later phases.
  env.NODE_OPTIONS = lib.optionalString stdenv.hostPlatform.isAarch64 "--jitless";

  preBuild = lib.optionalString stdenv.hostPlatform.isAarch64 ''
    wrapperDir="$TMPDIR/node-single-threaded"
    mkdir -p "$wrapperDir"
    makeWrapper ${nodejs}/bin/node "$wrapperDir/node" --add-flags "--single-threaded"
    makeWrapper ${nodejs}/bin/node "$wrapperDir/npm" --add-flags "--single-threaded ${nodejs}/lib/node_modules/npm/bin/npm-cli.js"
    export PATH="$wrapperDir:$PATH"
    unset NODE_OPTIONS
  '';

  postBuild = lib.optionalString stdenv.hostPlatform.isAarch64 ''
    export NODE_OPTIONS=--jitless
  '';

  meta = {
    description = "Model Context Protocol (MCP) server for Todoist";
    homepage = "https://github.com/Doist/todoist-mcp";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "todoist-mcp";
  };
})
