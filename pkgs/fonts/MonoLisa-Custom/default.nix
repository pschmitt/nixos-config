{
  lib,
  pkgs,
  stdenvNoCC,
  python3Packages,
}:

stdenvNoCC.mkDerivation rec {
  pname = "MonoLisa-Custom";
  version = "1.808";

  src = ../src/MonoLisa-Plus-Custom-1.808.zip;

  nativeBuildInputs = with pkgs; [ unzip ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/truetype
    unzip -j $src -d $out/share/fonts/truetype
  '';

  meta = with lib; {
    homepage = "https://www.monolisa.dev";
    description = "font follows function";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
