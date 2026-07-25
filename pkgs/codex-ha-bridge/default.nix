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
    rev = "6ff7e89c05a95c1611c259400a3b4f88adc9f5d8";
    hash = "sha256-oyGXxYUL7yXrlN6oIG6NNjMYFvfITN31PvhezMCRmcw=";
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
