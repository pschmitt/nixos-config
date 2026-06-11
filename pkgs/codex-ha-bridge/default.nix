{
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
}:

stdenv.mkDerivation {
  pname = "codex-ha-bridge";
  version = "0-unstable-2026-05-05";

  src = fetchFromGitHub {
    owner = "ofilis";
    repo = "codex-ha-bridge";
    rev = "492e949b8d014f3bf160db846be9522a971d6bfd";
    hash = "sha256-QPchKcH5GkseS4E4ghhy727ew9EfmYJhaT7mEQXDBNI=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/codex-ha-bridge
    cp -r src package.json $out/lib/codex-ha-bridge/
    makeWrapper ${nodejs}/bin/node $out/bin/codex-ha-bridge \
      --add-flags "$out/lib/codex-ha-bridge/src/index.js"
    runHook postInstall
  '';

  meta = {
    description = "Publish OpenAI Codex usage limits to Home Assistant over MQTT";
    homepage = "https://github.com/ofilis/codex-ha-bridge";
    mainProgram = "codex-ha-bridge";
  };
}
