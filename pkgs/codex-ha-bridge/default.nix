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
  version = "unstable-2026-07-29";

  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "codex-ha-bridge";
    rev = "ad9730f59b81302b5ba803aca99e2d0869d26b85";
    hash = "sha256-anfGZ+DU+CYr+RzIzGfzKFw40gY2mjiiplhSWXj6w+4=";
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
