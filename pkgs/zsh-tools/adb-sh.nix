{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  android-tools,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  iproute2,
  jq,
  nmap,
  perl,
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
  pname = "adb-sh";
  version = "unstable-2026-09-26";
  inherit src;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    install -Dm755 "$src/adb.sh" "$out/bin/adb.sh"
    cp -r "$src/lib" "$out/bin/lib"
    wrapProgram "$out/bin/adb.sh" --prefix PATH : ${
      lib.makeBinPath [
        android-tools
        coreutils
        gawk
        gnugrep
        gnused
        iproute2
        jq
        nmap
        perl
      ]
    }
  '';

  meta = {
    description = "Android device control helpers built on adb";
    homepage = "https://github.com/pschmitt/adb.sh";
    license = lib.licenses.mit;
    mainProgram = "adb.sh";
    platforms = lib.platforms.unix;
  };
}
