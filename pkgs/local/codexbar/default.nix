{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.56.7";
  sources = {
    x86_64-linux = {
      target = "linux-musl-x86_64";
      hash = "sha256-eEtvnZ4+T9NeLQ/27oP6sE0aMvOhMjtfvuRXqQTGLNA=";
    };
    aarch64-linux = {
      target = "linux-musl-aarch64";
      hash = "sha256-u6CMUJlm7NbDMYUauVO3Alz5VNHQebrkY1GUN7BXQQw=";
    };
  };
  currentSystem = stdenvNoCC.hostPlatform.system;
  srcInfo = sources.${currentSystem} or (throw "Unsupported platform for codexbar: ${currentSystem}");
in
stdenvNoCC.mkDerivation {
  pname = "codexbar";
  inherit version;

  src = fetchurl {
    url = "https://github.com/steipete/CodexBar/releases/download/v${version}/CodexBarCLI-v${version}-${srcInfo.target}.tar.gz";
    inherit (srcInfo) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 CodexBarCLI $out/bin/CodexBarCLI
    ln -s CodexBarCLI $out/bin/codexbar
    if [ -d CodexBar_CodexBarCore.bundle ]; then
      cp -a CodexBar_CodexBarCore.bundle $out/bin/
    fi
    runHook postInstall
  '';

  meta = {
    description = "CLI for CodexBar, monitoring AI provider usage and quotas";
    homepage = "https://github.com/steipete/CodexBar";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "codexbar";
  };
}
