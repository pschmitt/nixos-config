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
  kubecolor,
  kubectl,
}:
let
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "kubectl-watch";
    rev = "ef9c471190758f784f4bd55f6c1a8ccdfb54bee3";
    hash = "sha256-QFLRotDzn07UNWJfIEvhCDD7bY/JA6pecq0GUXiU0Y4=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "kubectl-watch";
  version = "unstable-2026-09-26";
  inherit src;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    install -Dm755 "$src/kubectl-watch" "$out/bin/kubectl-watch"
    patchShebangs "$out/bin/kubectl-watch"
    wrapProgram "$out/bin/kubectl-watch" --prefix PATH : ${
      lib.makeBinPath [
        coreutils
        gawk
        gnugrep
        gnused
        jq
        kubecolor
        kubectl
      ]
    }
  '';
  meta = {
    description = "Watch resources using kubectl";
    homepage = "https://github.com/pschmitt/kubectl-watch";
    license = lib.licenses.mit;
    mainProgram = "kubectl-watch";
  };
}
