{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  bind,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  inetutils,
  netcat-openbsd,
  util-linux,
}:
let
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "tesmart.sh";
    rev = "2f9d2e303691c48bf398e7825373cb8555cf7f67";
    hash = "sha256-UGtdelbVp9JaZKVZOyatGSxuJr9BJkfnj6ryoFbq1K8=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "tesmart-cli";
  version = "unstable-2026-09-26";
  inherit src;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    install -Dm755 "$src/tesmart.sh" "$out/bin/tesmart"
    patchShebangs "$out/bin/tesmart"
    wrapProgram "$out/bin/tesmart" --prefix PATH : ${
      lib.makeBinPath [
        bash
        bind
        coreutils
        gawk
        gnugrep
        gnused
        inetutils
        netcat-openbsd
        util-linux
      ]
    }
  '';
  meta = {
    description = "CLI for TESmart KVM switches";
    homepage = "https://github.com/pschmitt/tesmart.sh";
    license = lib.licenses.mit;
    mainProgram = "tesmart";
  };
}
