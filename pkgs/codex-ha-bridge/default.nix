{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
  nix-update-script,
}:

stdenv.mkDerivation {
  pname = "codex-ha-bridge";
  version = "unstable-2026-07-25";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "codex-ha-bridge";
    rev = "4de94cc7680c543f2ca504d4814657b9678ba671";
    hash = "sha256-ELkViY2a/pPU+KXNAe0eMVIDZEll15AMsGo2ONNW3Ho=";
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

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version"
      "branch"
    ];
  };

  meta = {
    description = "Publish OpenAI Codex usage limits to Home Assistant over MQTT";
    homepage = "https://github.com/pschmitt/codex-ha-bridge";
    license = lib.licenses.mit;
    mainProgram = "codex-ha-bridge";
  };
}
