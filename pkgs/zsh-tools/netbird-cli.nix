{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  coreutils,
  curl,
  gawk,
  gnugrep,
  gnused,
  jq,
  util-linux,
}:
let
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "netbird-cli";
    rev = "dd7d56742f3f515538a2bc952a23a2f7d43febaa";
    hash = "sha256-nbAY05jBJNbAOgeEiVBlaiShmtSzOAyL1RfCSLmll8E=";
  };
in
stdenvNoCC.mkDerivation {
  inherit src;

  pname = "netbird-cli";
  version = "unstable-2026-09-26";
  nativeBuildInputs = [ makeWrapper ];
  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    install -Dm755 ${src}/netbird-cli.sh "$out/bin/netbird-cli"
    patchShebangs "$out/bin/netbird-cli"
    wrapProgram "$out/bin/netbird-cli" --prefix PATH : ${
      lib.makeBinPath [
        coreutils
        curl
        gawk
        gnugrep
        gnused
        jq
        util-linux
      ]
    }
  '';
  meta = {
    description = "NetBird management API command-line client";
    homepage = "https://github.com/pschmitt/netbird-cli";
    license = lib.licenses.mit;
    mainProgram = "netbird-cli";
  };
}
