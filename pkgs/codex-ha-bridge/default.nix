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
  version = "unstable-2026-07-17";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "codex-ha-bridge";
    rev = "91c6fb35e864b43518fe8b0dc3a0224e853e35d2";
    hash = "sha256-dHylTDb32sXN7UelAqfG8n2jomp6tNFg7d4rd/c0bbI=";
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
