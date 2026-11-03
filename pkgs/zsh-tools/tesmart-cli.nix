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
    rev = "33330dad595c9e17733df6fad5bf0045d14a452a";
    hash = "sha256-9tQX/wUWLF6nu7mJeGm6qrnc6bvwAbSmapBA2aVo55A=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "tesmart-cli";
  version = "0-unstable-2026-11-01";
  passthru.updatePolicy.autoMerge = "all";
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
