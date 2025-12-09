{
  lib,
  pkgs,
  stdenvNoCC,
  requireFile,
}:

stdenvNoCC.mkDerivation {
  pname = "MonoLisa";
  version = "1.808";

  src = requireFile {
    name = "MonoLisa-Plus-Custom-1.808.zip";
    url = "https://blobs.brkn.lol/private/fonts/MonoLisa-Plus-Custom-1.808.zip";
    sha256 = "sha256-twWp1sFAx6TYT9UjNbyVfH07+tQtZDG1D4atYTO4AQA=";
  };

  nativeBuildInputs = with pkgs; [ unzip ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/opentype
    unzip -j $src -d $out/share/fonts/opentype
  '';

  meta = with lib; {
    homepage = "https://www.monolisa.dev";
    description = "font follows function";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
