{
  lib,
  pkgs,
  stdenvNoCC,
  requireFile,
}:

stdenvNoCC.mkDerivation {
  pname = "MonoLisaNF";
  version = "1.808";

  src = requireFile {
    name = "MonoLisa-Plus-Custom-1.808.zip";
    url = "https://blobs.brkn.lol/private/fonts/MonoLisa-Plus-Custom-1.808.zip";
    sha256 = "sha256-twWp1sFAx6TYT9UjNbyVfH07+tQtZDG1D4atYTO4AQA=";
  };

  nativeBuildInputs = with pkgs; [
    nerd-font-patcher
    unzip
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/opentype extracted
    unzip -j $src -d extracted

    for f in extracted/*
    do
      # patch font
      nerd-font-patcher $f --complete --no-progressbars \
        --outputdir $out/share/fonts/opentype
    done
  '';

  meta = with lib; {
    homepage = "https://www.monolisa.dev";
    description = "font follows function";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
