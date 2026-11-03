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
    rev = "2b1bc0658549f2025d0074fbad2446d86e79f06e";
    hash = "sha256-pUxI36Jcf0CkMlcqNJnlqMVIhy3QQjwJ8JhsxtxFf7k=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "kubectl-ksh";
  version = "0-unstable-2026-11-01";
  passthru.updatePolicy.autoMerge = "all";
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
