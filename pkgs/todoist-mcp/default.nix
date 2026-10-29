{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
}:

buildNpmPackage rec {
  pname = "todoist-mcp";
  version = "13.7.2";

  src = fetchFromGitHub {
    owner = "Doist";
    repo = "todoist-mcp";
    rev = "v${version}";
    hash = "sha256-Fc/EfHtQ8FkeLyz0JJY+Xh140aJn+yToifmXT1FY238=";
  };

  npmDepsHash = "sha256-XfekrUnXwhRPfW1h+DKLQWMO4LfcTQ4EZt4dvqwR6zM=";

  doCheck = false;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isAarch64 [ makeWrapper ];

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

  passthru.updatePolicy.autoMerge = "patch";

  meta = {
    description = "Model Context Protocol (MCP) server for Todoist";
    homepage = "https://github.com/Doist/todoist-mcp";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "todoist-mcp";
  };
}
