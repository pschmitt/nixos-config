{
  lib,
  stdenv,
  nodejs,
  msteams-mcp,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "teams-live";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/teams-live"
    cp -r src package.json "$out/lib/teams-live/"

    mkdir -p "$out/lib/teams-live/node_modules"
    ln -s "${msteams-mcp}/lib/node_modules/msteams-mcp" "$out/lib/teams-live/node_modules/msteams-mcp"

    mkdir -p "$out/bin"
    makeWrapper "${lib.getExe nodejs}" "$out/bin/teams-live" \
      --add-flags "$out/lib/teams-live/src/main.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Microsoft Teams push watcher and GitLab MR integration";
    license = lib.licenses.mit;
    mainProgram = "teams-live";
  };
}
