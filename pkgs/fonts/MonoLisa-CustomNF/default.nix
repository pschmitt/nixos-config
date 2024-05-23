{
  lib,
  pkgs,
  stdenvNoCC,
  python3Packages,
}:

stdenvNoCC.mkDerivation rec {
  pname = "MonoLisa-CustomNF";
  version = "1.808";

  src = ../src/MonoLisa-Plus-Custom-1.808.zip;

  nativeBuildInputs = with pkgs; [
    nerd-font-patcher
    unzip
  ];

  phases = [ "buildPhase" ];

  buildPhase = ''
    mkdir -p $out/share/fonts/truetype extracted
    unzip -j $src -d extracted

    for f in extracted/*
    do
      # Nerdify font
      nerd-font-patcher $f --complete --no-progressbars \
        --outputdir $out/share/fonts/truetype
    done
  '';

  meta = with lib; {
    homepage = "https://www.monolisa.dev";
    description = "font follows function";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
