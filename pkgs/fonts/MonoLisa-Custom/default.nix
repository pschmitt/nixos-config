{
  lib,
  pkgs,
  stdenvNoCC,
  requireFile,
}:

stdenvNoCC.mkDerivation {
  pname = "MonoLisa-Custom";
  version = "1.808";

  src = requireFile {
    name = "MonoLisa-Plus-Custom-1.808.zip";
    url = "https://blobs.brkn.lol/private/fonts/MonoLisa-Plus-Custom-1.808.zip";
    sha256 = "sha256-twWp1sFAx6TYT9UmM1vIV8fTv61C2E0RwbhQ+GrWEzg=";
  };

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
