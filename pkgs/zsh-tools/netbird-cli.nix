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
    rev = "d0685d37cef3986533ce1ee0897155ec834798df";
    hash = "sha256-AjYkxZW41NxPUe7wdG1bH+a6YFKFYxr5LKHdxa6bmOU=";
  };
in
stdenvNoCC.mkDerivation {
  inherit src;

  pname = "netbird-cli";
  version = "0-unstable-2026-11-01";
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
