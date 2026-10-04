{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  jq,
  kubectl,
  util-linux,
}:
let
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "k.sh";
    rev = "a3a85afb4115e8d3d2a4a22082cda3a3e9ac7bbf";
    hash = "sha256-ZwUcP3rNCRgbq+tCd5d3AZWbqEgZaFkBrTLgKkh8PAw=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "kubectl-ksh";
  version = "unstable-2026-09-26";
  inherit src;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    mkdir -p "$out/bin"
    install -m755 "$src/kubectl-delete-all.sh" "$out/bin/kubectl-delete_all"
    install -m755 "$src/kubectl-list-all.sh" "$out/bin/kubectl-list_all"
    install -m755 "$src/kubectl-reveal-secret.sh" "$out/bin/kubectl-reveal_secret"
    patchShebangs "$out/bin"
    for program in "$out"/bin/*; do
      wrapProgram "$program" --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gawk
          gnugrep
          gnused
          jq
          kubectl
          util-linux
        ]
      }
    done
  '';
  meta = {
    description = "kubectl command line helpers from k.sh";
    homepage = "https://github.com/pschmitt/k.sh";
    license = lib.licenses.mit;
  };
}
