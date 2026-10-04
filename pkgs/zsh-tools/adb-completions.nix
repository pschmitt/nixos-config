{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
let
  src = fetchFromGitHub {
    owner = "pschmitt";
    repo = "adb.sh";
    rev = "6b71752c862069af7b6ee15c3da694d35be87e5d";
    hash = "sha256-ey4k1vWK00e+t+y3UQKAtssOV5ezCgcvPhupTH8CzyI=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "adb-zsh-completions";
  version = "unstable-2026-09-26";
  inherit src;
  dontBuild = true;
  dontConfigure = true;
  installPhase = ''
    install -Dm444 "$src/_adb.sh" "$out/share/zsh/site-functions/_adb"
  '';
  meta = {
    description = "Zsh completion for Android Debug Bridge";
    homepage = "https://github.com/pschmitt/adb.sh";
    license = lib.licenses.mit;
  };
}
