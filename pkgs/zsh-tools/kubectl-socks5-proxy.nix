{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  kubectl,
  ncurses,
  util-linux,
}:
let
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "kubectl-plugin-socks5-proxy";
    rev = "2bae6e33445f5eb3d2e924e9eced5d9025327355";
    hash = "sha256-gdUmvrCVHfEdaNpDLawa5+J7U495Ll8rIxx3N0owCPk=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "kubectl-socks5-proxy";
  version = "unstable-2026-09-26";
  inherit src;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    install -Dm755 "$src/kubectl-socks5-proxy" "$out/bin/kubectl-socks5_proxy"
    patchShebangs "$out/bin/kubectl-socks5_proxy"
    wrapProgram "$out/bin/kubectl-socks5_proxy" --prefix PATH : ${
      lib.makeBinPath [
        coreutils
        gawk
        gnugrep
        gnused
        kubectl
        ncurses
        util-linux
      ]
    }
  '';
  meta = {
    description = "SOCKS5 proxy kubectl plugin";
    homepage = "https://github.com/pschmitt/kubectl-plugin-socks5-proxy";
    license = lib.licenses.mit;
    mainProgram = "kubectl-socks5_proxy";
  };
}
